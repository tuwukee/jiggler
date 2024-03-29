# frozen_string_literal: true

RSpec.describe Jiggler::Summary do
  let(:queues) { ['default', 'queue1'] }
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1,
      timeout: 1,
      stats_interval: 1,
      queues: queues,
      poller_enabled: false,
      mode: :at_most_once
    )
  end
  let(:uuid) { "#{SecureRandom.hex(3)}-test" }
  let(:collection) { Jiggler::Stats::Collection.new(uuid, uuid) }
  let(:acknowledger) { Jiggler::AtMostOnce::Acknowledger.new(config) }
  let(:fetcher) { Jiggler::AtMostOnce::Fetcher.new(config, collection) }
  let(:summary) { described_class.new(config) }

  describe '.all' do
    it 'has correct keys and data types' do
      subject = summary.all
      expect(subject).to be_a Hash
      expect(subject.keys).to eq Jiggler::Summary::KEYS
      expect(subject['retry_jobs_count']).to be_a Integer
      expect(subject['dead_jobs_count']).to be_a Integer
      expect(subject['scheduled_jobs_count']).to be_a Integer
      expect(subject['processed_count']).to be_a Integer
      expect(subject['failures_count']).to be_a Integer
      expect(subject['monitor_enabled']).to be_a(String).or be_a(NilClass)
      expect(subject['processes']).to be_a Hash
      expect(subject['queues']).to be_a Hash
    end

    it 'gets latest data' do
      Sync do
        config.cleaner.prune_all
        launcher = Jiggler::Launcher.new(config)
        uuid = launcher.send(:identity)
        MyJob.with_options(queue: 'queue1').enqueue
        
        first_summary = summary.all
        expect(first_summary['queues']).to include({
          'queue1' => 1
        })
        expect(first_summary['processes'].keys).to_not include(uuid)
        
        second_summary = nil
        launcher_task = Async { launcher.start }
        stop_task = Async do
          sleep(2)
          second_summary = summary.all
          launcher.stop
        end
        launcher_task.wait
        stop_task.wait

        expect(second_summary['queues']).to_not include({
          'queue1' => 1
        })
        expect(second_summary['processes'].keys).to include(uuid)
        expect(second_summary['processes'][uuid]).to include({
          'queues' => queues.join(','),
          'hostname' => Socket.gethostname,
          'pid' => Process.pid.to_s,
          'concurrency' => '1',
          'timeout' => '1',
          'poller_enabled' => false,
          'current_jobs' => {}
        })
      end
    end

    context 'key dissasembly' do
      let(:uuid) { 'jiggler:svr:2aa9:10:15:drop,bark,meow:1:1673820635:29677:dyno:1' }

      it 'has correct process metadata' do
        allow(summary).to receive(:fetch_processes).and_return([uuid])
        subject = summary.all
        expect(subject['processes'][uuid]).to include({
          'name' => 'jiggler:svr:2aa9',
          'concurrency' => '10',
          'timeout' => '15',
          'queues' => 'drop,bark,meow',
          'pid' => '29677',
          'poller_enabled' => true,
          'started_at' => '1673820635',
          'hostname' => 'dyno:1',
        })
      end
    end
  end

  describe '#last_dead_jobs' do
    it 'returns last n dead jobs' do
      # clean data and enqueue a failling job with no retries
      Sync do 
        config.cleaner.prune_all
        expect(summary.last_dead_jobs(1)).to be_empty
        MyFailedJob.with_options(queue: 'queue1', retries: 0).enqueue('yay')
      end
      worker = Jiggler::Worker.new(config, collection, acknowledger, fetcher) do
        config.logger.info('Doing some weird dead testings')
      end
      task = Async do
        Async do
          worker.run
        end
        sleep(1)
        worker.terminate
      end
      task.wait

      # ensure the job is saved as dead
      jobs = Sync { summary.last_dead_jobs(3) }
      expect(jobs.count).to be 1
      expect(jobs.first).to include({
        'name' => 'MyFailedJob',
        'args' => ['yay']
      })
    end
  end

  describe '#last_retry_jobs' do
    it 'returns last n retry jobs' do
      # clean data and enqueue 5 failling jobs
      Sync do
        config.cleaner.prune_all
        expect(summary.last_retry_jobs(3)).to be_empty
        5.times do |i|
          MyFailedJob.with_options(
            queue: 'queue1', 
            retries: 1
          ).enqueue("yay-#{i}")
        end
      end
      
      worker = Jiggler::Worker.new(config, collection, acknowledger, fetcher) do
        config.logger.info('Doing some weird retry testings')
      end
      
      # start worker, wait for 1 sec, terminate worker
      task = Async do
        Async do
          worker.run
        end
        sleep(1)
        worker.terminate
      end
      task.wait

      # fetch last 3 retry jobs to ensure they are in the right order
      jobs = Sync { summary.last_retry_jobs(3) }
      puts jobs.first
      expect(jobs.count).to be 3
      expect(jobs.first).to include({
        'name' => 'MyFailedJob',
        'args' => ['yay-4']
      })
    end
  end

  describe '#last_scheduled_jobs' do
    it 'returns last n scheduled jobs' do
      Sync do 
        config.cleaner.prune_all
        expect(summary.last_scheduled_jobs(3)).to be_empty
        MyFailedJob.with_options(
          queue: 'queue1'
        ).enqueue_in(100, 'yay-scheduled')
        jobs = summary.last_scheduled_jobs(3)
        expect(jobs.count).to be 1
        expect(jobs.first).to include({
          'name' => 'MyFailedJob',
          'args' => ['yay-scheduled']
        })
        expect(jobs.first['scheduled_at']).to be_a Float
      end
    end
  end
end
