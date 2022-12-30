# frozen_string_literal: true

RSpec.describe Jiggler::Summary do
  let(:queues) { ['default', 'queue1'] }
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1,
      timeout: 1,
      queues: queues,
      poller_enabled: false,
      server_mode: true
    )
  end
  let(:collection) { Jiggler::Stats::Collection.new('summary-test-uuid') } 
  let(:summary) { described_class.new(config) }

  describe '.all' do
    xit 'has correct keys and data types' do
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
      Sync { config.cleaner.prune_all }
      task = Async do
        launcher = Jiggler::Launcher.new(config)
        uuid = launcher.send(:uuid)
        MyJob.with_options(queue: 'queue1').enqueue
        
        first_summary = Sync { summary.all }
        expect(first_summary['queues']).to include({
          'queue1' => 1
        })
        expect(first_summary['processes'].keys).to_not include(uuid)
        
        launcher_task = Async { launcher.start }
        second_summary = nil
        stop_task = Async do
          sleep(1)
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
      task.wait
    end
  end

  describe '#last_dead_jobs' do
    it 'returns last n dead jobs' do
      Sync do 
        config.cleaner.prune_all
        expect(summary.last_dead_jobs(1)).to be_empty
        MyFailedJob.with_options(queue: 'queue1', retries: 0).enqueue('yay')
      end
      worker = Jiggler::Worker.new(config, collection) do
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
      worker = Jiggler::Worker.new(config, collection) do
        config.logger.info('Doing some weird retry testings')
      end
      task = Async do
        Async do
          worker.run
        end
        sleep(1)
        worker.terminate
      end
      task.wait
      jobs = Sync { summary.last_retry_jobs(3) }
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
