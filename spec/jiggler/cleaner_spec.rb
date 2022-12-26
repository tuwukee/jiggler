# frozen_string_literal: true

RSpec.describe Jiggler::Cleaner do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1, 
      timeout: 1, 
      verbose: true,
      poller_enabled: false,
      redis_mode: :async
    )
  end
  let(:cleaner) { described_class.new(config) }
  after(:all) { Jiggler.config.cleaner.prune_all }

  describe '#prune_failures_counter' do
    it 'prunes the failures counter' do
      config.with_sync_redis do |conn|
        conn.call('SET', Jiggler::Stats::Monitor::FAILURES_COUNTER, 5)
      end
      cleaner.prune_failures_counter
      config.with_sync_redis do |conn|
        expect(conn.call('GET', Jiggler::Stats::Monitor::FAILURES_COUNTER)).to be nil
      end
    end
  end

  describe '#prune_processed_counter' do
    it 'prunes the processed counter' do
      config.with_sync_redis do |conn|
        conn.call('SET', Jiggler::Stats::Monitor::PROCESSED_COUNTER, 5)
      end
      cleaner.prune_processed_counter
      config.with_sync_redis do |conn|
        expect(conn.call('GET', Jiggler::Stats::Monitor::PROCESSED_COUNTER)).to be nil
      end
    end
  end

  describe '#prune_all_processes' do
    it 'prunes all processes' do
      config.with_sync_redis do |conn|
        conn.call(
          'HSET', 
          config.processes_hash, 
          'uuid-cleaner-test-0', 
          '{}'
        )
      end
      cleaner.prune_all_processes
      config.with_sync_redis do |conn|
        expect(conn.call('HGETALL', config.processes_hash)).to be_empty
      end
    end
  end

  describe '#prune_process' do
    it 'prunes a process by its uuid' do
      config.with_sync_redis do |conn|
        conn.call(
          'HSET', 
          config.processes_hash, 
          'uuid-cleaner-test-1', 
          '{}'
        )
      end
      cleaner.prune_process('uuid-cleaner-test-1')
      config.with_sync_redis do |conn|
        expect(
          conn.call('HGETALL', config.processes_hash).keys
        ).to_not include('uuid-cleaner-test-1')
      end
    end
  end

  describe '#prune_dead_set' do
    it 'prunes the dead set' do
      config.with_sync_redis do |conn|
        conn.call('ZADD', config.dead_set, 1, '{}')
      end
      cleaner.prune_dead_set
      config.with_sync_redis do |conn|
        expect(conn.call('ZCARD', config.dead_set)).to be 0
      end
    end
  end

  describe '#prune_retries_set' do
    it 'prunes the retries set' do
      config.with_sync_redis do |conn|
        conn.call('ZADD', config.retries_set, 1, '{}')
      end
      cleaner.prune_retries_set
      config.with_sync_redis do |conn|
        expect(conn.call('ZCARD', config.retries_set)).to be 0
      end
    end
  end

  describe '#prune_scheduled_set' do
    it 'prunes the scheduled set' do
      config.with_sync_redis do |conn|
        conn.call('ZADD', config.scheduled_set, 1, '{}')
      end
      cleaner.prune_scheduled_set
      config.with_sync_redis do |conn|
        expect(conn.call('ZCARD', config.scheduled_set)).to be 0
      end
    end
  end

  describe '#prune_all_queues' do
    it 'prunes all queues' do
      config.with_sync_redis do |conn|
        conn.call('LPUSH', 'jiggler:list:cleaner-test', '{}')
      end
      cleaner.prune_all_queues
      config.with_sync_redis do |conn|
        expect(conn.call('LRANGE', 'jiggler:list:cleaner-test-0', 0, -1)).to be_empty
      end
    end
  end

  describe '#prune_queue' do
    it 'prunes a queue by its name' do
      config.with_sync_redis do |conn|
        conn.call('LPUSH', 'jiggler:list:cleaner-test-1', '{}')
        conn.call('LPUSH', 'jiggler:list:cleaner-test-2', '{}')
      end
      cleaner.prune_queue('cleaner-test-1')
      config.with_sync_redis do |conn|
        expect(conn.call('LRANGE', 'jiggler:list:cleaner-test-1', 0, -1)).to be_empty
        expect(conn.call('LRANGE', 'jiggler:list:cleaner-test-2', 0, -1)).to eq(['{}'])
      end
    end
  end

  describe '#prune_outdated_processes_data' do
    let(:processes_data) do
      [
        'uuid1-cleaner', '{}',
        'uuid2-cleaner', '{}',
        'uuid3-cleaner', '{}',
        'uuid4-cleaner', '{}'
      ]
    end
    let(:stats_keys) { ['#{config.stats_prefix}uuid3'] }

    it 'prunes processes data without uptodate stats' do
      config.with_sync_redis do |conn|
        conn.call('HSET', config.processes_hash, *processes_data)
        conn.call('SET', "#{config.stats_prefix}uuid1-cleaner", '{}')
      end
      cleaner.prune_outdated_processes_data
      config.with_sync_redis do |conn|
        expect(
          conn.call('HGETALL', config.processes_hash)
        ).to eq({ 
          'uuid1-cleaner'=> '{}'
        })
      end
    end
  end

  describe '#unforsed_prune_outdated_processes_data' do
    it 'sets cleaner flag to prevent multiple prunes from concurrent processes' do
      cleaner.unforced_prune_outdated_processes_data
      config.with_sync_redis do |conn|
        expect(conn.call('GET', 'jiggler:flag:cleanup')).to eq('1')
      end
    end
  end

  describe '#prune_all' do
    it 'prunes all data' do
      cleaner.prune_all
      config.with_sync_redis do |conn|
        expect(conn.call('HGETALL', config.processes_hash)).to be_empty
        expect(conn.call('SMEMBERS', config.dead_set)).to be_empty
        expect(conn.call('SMEMBERS', config.retries_set)).to be_empty
        expect(conn.call('SMEMBERS', config.scheduled_set)).to be_empty
        expect(conn.call('KEYS', "#{config.queue_prefix}*")).to be_empty
        expect(conn.call('GET', Jiggler::Stats::Monitor::FAILURES_COUNTER)).to be nil
        expect(conn.call('GET', Jiggler::Stats::Monitor::PROCESSED_COUNTER)).to be nil      
      end
    end
  end
end
