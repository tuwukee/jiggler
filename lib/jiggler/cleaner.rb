# frozen_string_literal: true

module Jiggler
  class Cleaner
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def prune_all(pool: config.client_redis_pool)
      pool.acquire do |conn|
        conn.pipelined do |pipeline|
          prn_retries_set(pipeline)
          prn_scheduled_set(pipeline)
          prn_dead_set(pipeline)
          prn_failures_counter(pipeline)
          prn_processed_counter(pipeline)
        end
        prn_all_queues(conn)
        prn_all_processes(conn)
      end
    end

    def prune_failures_counter(pool: config.client_redis_pool)
      pool.acquire do |conn|
        prn_failures_counter(conn)
      end
    end

    def prune_processed_counter(pool: config.client_redis_pool)
      pool.acquire do |conn|
        prn_processed_counter(conn)
      end
    end

    def prune_all_processes(pool: config.client_redis_pool)
      pool.acquire do |conn|
        prn_all_processes(conn)
      end
    end

    def prune_process(name:, pool: config.client_redis_pool)
      hex = name.split(':').last
      pool.acquire do |conn|
        processes = conn.call('SCAN', '0', 'MATCH', "#{config.server_prefix}#{hex}*").last
        count = processes.count
        if count == 0
          config.logger.error("No process found for #{name}")
          return
        elsif count > 1
          config.logger.error("Multiple processes found for #{name}, not pruning #{processes}")
          return
        end
        conn.call('DEL', processes.first)
      end
    end

    def prune_dead_set(pool: config.client_redis_pool)
      pool.acquire do |conn|
        prn_dead_set(conn)
      end
    end

    def prune_retries_set(pool: config.client_redis_pool)
      pool.acquire do |conn|
        prn_retries_set(conn)
      end
    end

    def prune_scheduled_set(pool: config.client_redis_pool)
      pool.acquire do |conn|
        prn_scheduled_set(conn)
      end
    end

    def prune_all_queues(pool: config.client_redis_pool)
      pool.acquire do |conn|
        prn_all_queues(conn)
      end
    end

    def prune_queue(name:, pool: config.client_redis_pool)
      pool.acquire do |conn|
        conn.call('DEL', "#{config.queue_prefix}#{name}")
      end
    end

    private

    def prn_retries_set(conn)
      conn.call('DEL', config.retries_set)
    end

    def prn_scheduled_set(conn)
      conn.call('DEL', config.scheduled_set)
    end

    def prn_dead_set(conn)
      conn.call('DEL', config.dead_set)
    end

    def prn_all_queues(conn)
      queues = conn.call('SCAN', '0', 'MATCH', config.queue_scan_key).last
      conn.call('DEL', *queues) unless queues.empty?
    end

    def prn_all_processes(conn)
      processes = conn.call('SCAN', '0', 'MATCH', config.process_scan_key).last
      conn.call('DEL', *processes) unless processes.empty?
    end

    def prn_failures_counter(conn)
      conn.call('DEL', Jiggler::Stats::Monitor::FAILURES_COUNTER)
    end

    def prn_processed_counter(conn)
      conn.call('DEL', Jiggler::Stats::Monitor::PROCESSED_COUNTER)
    end
  end
end
