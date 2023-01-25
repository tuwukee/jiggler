# frozen_string_literal: true

RSpec.describe Jiggler::Cleaner do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1,
      timeout: 1,
      poller_enabled: false,
      async_client: false
    )
  end
  let(:cleaner) { described_class.new(config) }
  after(:all) { Jiggler.config.cleaner.prune_all }

  describe '#prune_failures_counter' do
    it 'prunes the failures counter' do
      config.client_redis_pool.acquire do |conn|
        conn.call('SET', config.failures_counter, 5)
      end
      cleaner.prune_failures_counter
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('GET', config.failures_counter)).to be nil
      end
    end
  end

  describe '#prune_processed_counter' do
    it 'prunes the processed counter' do
      config.client_redis_pool.acquire do |conn|
        conn.call('SET', config.processed_counter, 5)
      end
      cleaner.prune_processed_counter
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('GET', config.processed_counter)).to be nil
      end
    end
  end

  describe '#prune_all_processes' do
    it 'prunes all processes' do
      config.client_redis_pool.acquire do |conn|
        conn.call(
          'SET',
          'jiggler:svr:uuid-cleaner-test-0:process', 
          '{}',
          ex: 10
        )
      end
      cleaner.prune_all_processes
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('SCAN', '0', 'MATCH', config.process_scan_key).last).to be_empty
      end
    end
  end

  describe '#prune_process' do
    let(:uuid) { 'jiggler:svr:uuid-cleaner-test-1:process' }
    it 'prunes a process by its uuid' do
      config.client_redis_pool.acquire do |conn|
        conn.call(
          'SET',
          uuid,
          '{}',
          ex: 10
        )
      end
      cleaner.prune_process(uuid: uuid)
      config.client_redis_pool.acquire do |conn|
        expect(
          conn.call('GET', uuid)
        ).to be nil
      end
    end
  end

  describe '#prune_process_by_hex' do
    let(:uuid) { 'jiggler:svr:uuid-cleaner-test-2:process' }
    it 'prunes a process by its hex' do
      config.client_redis_pool.acquire do |conn|
        conn.call(
          'SET',
          uuid,
          '{}',
          ex: 10
        )
      end
      cleaner.prune_process_by_hex(hex: 'jiggler:svr:uuid-cleaner-test-2')
      config.client_redis_pool.acquire do |conn|
        expect(
          conn.call('GET', uuid)
        ).to be nil
      end
    end
  end

  describe '#prune_dead_set' do
    it 'prunes the dead set' do
      config.client_redis_pool.acquire do |conn|
        conn.call('ZADD', config.dead_set, 1, '{}')
      end
      cleaner.prune_dead_set
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('ZCARD', config.dead_set)).to be 0
      end
    end
  end

  describe '#prune_retries_set' do
    it 'prunes the retries set' do
      config.client_redis_pool.acquire do |conn|
        conn.call('ZADD', config.retries_set, 1, '{}')
      end
      cleaner.prune_retries_set
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('ZCARD', config.retries_set)).to be 0
      end
    end
  end

  describe '#prune_scheduled_set' do
    it 'prunes the scheduled set' do
      config.client_redis_pool.acquire do |conn|
        conn.call('ZADD', config.scheduled_set, 1, '{}')
      end
      cleaner.prune_scheduled_set
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('ZCARD', config.scheduled_set)).to be 0
      end
    end
  end

  describe '#prune_all_queues' do
    it 'prunes all queues' do
      config.client_redis_pool.acquire do |conn|
        conn.call('LPUSH', 'jiggler:list:cleaner-test', '{}')
      end
      cleaner.prune_all_queues
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('LRANGE', 'jiggler:list:cleaner-test-0', 0, -1)).to be_empty
      end
    end
  end

  describe '#prune_queue' do
    it 'prunes a queue by its name' do
      config.client_redis_pool.acquire do |conn|
        conn.call('LPUSH', 'jiggler:list:cleaner-test-1', '{}')
        conn.call('LPUSH', 'jiggler:list:cleaner-test-2', '{}')
      end
      cleaner.prune_queue(name: 'cleaner-test-1')
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('LRANGE', 'jiggler:list:cleaner-test-1', 0, -1)).to be_empty
        expect(conn.call('LRANGE', 'jiggler:list:cleaner-test-2', 0, -1)).to eq(['{}'])
      end
    end
  end

  describe '#prune_all' do
    it 'prunes all data' do
      cleaner.prune_all
      config.client_redis_pool.acquire do |conn|
        expect(conn.call('SCAN', '0', 'MATCH', config.process_scan_key).last).to be_empty
        expect(conn.call('SMEMBERS', config.dead_set)).to be_empty
        expect(conn.call('SMEMBERS', config.retries_set)).to be_empty
        expect(conn.call('SMEMBERS', config.scheduled_set)).to be_empty
        expect(conn.call('KEYS', "#{config.queue_prefix}*")).to be_empty
        expect(conn.call('GET', config.failures_counter)).to be nil
        expect(conn.call('GET', config.processed_counter)).to be nil      
      end
    end
  end
end
