# frozen_string_literal: true

RSpec.describe Jiggler::AtLeastOnce::Fetcher do
  describe '#fetch' do
    let(:config) do
      Jiggler::Config.new(
        concurrency: 1,
        timeout: 1,
        poller_enabled: false,
        queues: ['fetcher_queue'],
        mode: :at_least_once
      )
    end
    let(:uuid) { "#{SecureRandom.hex(3)}-test" }
    let(:reserve_queue) { 'jiggler:list:fetcher_queue:in_progress:' + uuid }
    let(:collection) { Jiggler::Stats::Collection.new(uuid, uuid) }
    let(:fetcher) { Jiggler::AtLeastOnce::Fetcher.new(config, collection) }

    after { config.cleaner.prune_all }

    it 'fetches current job' do
      MyJob.with_options(queue: 'fetcher_queue').enqueue
      job = nil
      task = Async do
        Async do
          fetcher.start
        end
        sleep(0.5)
        job = fetcher.fetch
        fetcher.suspend
      end
      task.wait
      args = Oj.load(job.args)

      expect(job.queue).to eq('jiggler:list:fetcher_queue')
      expect(job.reserve_queue).to eq(reserve_queue)

      expect(args['name']).to eq('MyJob')
      expect(args['jid']).to be_a(String)
      expect(args['retries']).to be 0
      expect(args['args']).to eq([])
      config.with_sync_redis do |conn|
        expect(conn.call('LLEN', reserve_queue)).to eq(1)
      end
    end

    it 'ack removes the job from reserve queue' do
      MyJob.with_options(queue: 'fetcher_queue').enqueue
      job = nil
      task = Async do
        Async do
          fetcher.start
        end
        sleep(0.5)
        job = fetcher.fetch
        fetcher.suspend
      end
      task.wait

      config.with_sync_redis do |conn|
        expect(conn.call('LLEN', reserve_queue)).to eq(1)
      end
      job.ack
      config.with_sync_redis do |conn|
        expect(conn.call('LLEN', reserve_queue)).to eq(0)
      end
    end
  end
end
