# frozen_string_literal: true

RSpec.describe Jiggler::Scheduled::Enqueuer do
  let(:config) do 
    Jiggler::Config.new(
      concurrency: 1, 
      timeout: 1, 
      verbose: true,
      queues: ['default', 'mine']
    )
  end
  let(:enqueuer) { described_class.new(config) }

  describe '#push_job' do
    it 'pushes an empty job to default queue' do
      expect do
        config.with_sync_redis do |conn|
          enqueuer.push_job(conn, '{ "name": "MyJob" }')
        end
      end.to change { 
        config.with_sync_redis { |conn| conn.call('LLEN', 'jiggler:list:default') }
      }.by(1)
    end

    it 'pushes job to queue from args' do
      expect do
        config.with_sync_redis do |conn|
          enqueuer.push_job(
            conn, 
            '{ "name": "MyJob", "queue": "mine" }'
          )
        end
      end.to change { 
        config.with_sync_redis { |conn| conn.call('LLEN', 'jiggler:list:mine') }
      }.by(1)
      config.with_sync_redis { |conn| conn.call('DEL', 'jiggler:list:mine') }
    end

    it 'does not drop job if queue is not configured' do
      expect do
        config.with_sync_redis do |conn|
          enqueuer.push_job(
            conn, 
            '{ "name": "MyJob", "queue": "unknown" }'
          )
        end
      end.to change { 
        config.with_sync_redis { |conn| conn.call('LLEN', 'jiggler:list:unknown') }
      }.by(1)
    end
  end

  describe '#enqueue_jobs' do
    it 'enqueues jobs if their zrange is in the past' do
      expect do
        config.with_sync_redis do |conn| 
          conn.call(
            'ZADD',
            config.retries_set, 
            (Time.now.to_f - 10.0).to_s, 
            '{ "name": "MyJob", "queue": "mine" }'
          )
          conn.call(
            'ZADD',
            config.retries_set, 
            (Time.now.to_f + 10.0).to_s,
            '{ "name": "MyFailedJob", "queue": "mine" }'
          )
          config.logger.debug('Enqueuer Test') { conn.call('ZRANGE', config.retries_set, -5, -1) }
        end
        expect(enqueuer).to receive(:push_job).at_least(:once).and_call_original
        Sync do
          enqueuer.enqueue_jobs
        end
      end.to change {
        config.with_sync_redis { |conn| conn.call('LLEN', 'jiggler:list:mine') }
      }.by(1)
      config.with_sync_redis { |conn| conn.call('DEL', 'jiggler:list:mine') }
    end
  end
end
