# frozen_string_literal: true

RSpec.describe Jiggler::Scheduled::Requeuer do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1,
      timeout: 1,
      poller_enabled: false,
      queues: ['my_queue']
    )
  end
  let(:launcher) { Jiggler::Launcher.new(config) }
  let(:identity) { launcher.send(:identity) }
  let(:uuid) { launcher.send(:uuid) }
  let(:requeuer) { Jiggler::Scheduled::Requeuer.new(config) }

  after { config.cleaner.prune_all }

  describe '#running_processes_uuid' do
    it 'fetches process uuids' do
      config.with_sync_redis do |conn|
        conn.call('SET', identity, 'test')
      end
      expect(requeuer.send(:running_processes_uuid)).to eq([uuid])
    end
  end

  describe '#requeue_data' do
    it 'selects data without running processes' do
      config.with_sync_redis do |conn|
        conn.call('SET', identity, 'test')
        conn.call('LPUSH', "jiggler:list:my_queue:in_progress:#{uuid}", 'test')
      end
      expect(requeuer.send(:requeue_data)).to eq([])
      config.with_sync_redis do |conn|
        conn.call('DEL', identity)
      end
      expect(requeuer.send(:requeue_data)).to eq([
        ["jiggler:list:my_queue:in_progress:#{uuid}", "jiggler:list:my_queue", uuid]
      ])
    end
  end

  describe '#handle_stale' do
    it 'requeues stale data' do
      config.with_sync_redis do |conn|
        conn.call('LPUSH', "jiggler:list:my_queue:in_progress:#{uuid}", 'test')
        expect(conn.call('LLEN', 'jiggler:list:my_queue')).to be 0
      end
      requeuer.handle_stale
      config.with_sync_redis do |conn|
        expect(conn.call('LLEN', "jiggler:list:my_queue:in_progress:#{uuid}")).to be 0
        expect(conn.call('LLEN', 'jiggler:list:my_queue')).to be 1
      end
    end
  end
end
