# frozen_string_literal: true

module Jiggler
  class Cleaner
    CLEANUP_FLAG = 'jiggler:flag:cleanup'
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def prune_all
      config.with_sync_redis do |conn|
        conn.pipelined do |pipeline|
          prn_retries_set(pipeline)
          prn_scheduled_set(pipeline)
          prn_dead_set(pipeline)
          prn_all_processes(pipeline)
          prn_failures_counter(pipeline)
          prn_processed_counter(pipeline)
        end
        prn_all_queues(conn)
      end
    end

    def prune_failures_counter
      config.with_sync_redis do |conn|
        prn_failures_counter(conn)
      end
    end

    def prune_processed_counter
      config.with_sync_redis do |conn|
        prn_processed_counter(conn)
      end
    end

    def prune_all_processes
      config.with_sync_redis do |conn|
        prn_all_processes(conn)
      end
    end

    def prune_process(uuid)
      config.with_sync_redis do |conn|
        conn.call('HDEL', config.processes_hash, uuid)
      end
    end

    def prune_dead_set
      config.with_sync_redis do |conn|
        prn_dead_set(conn)
      end
    end

    def prune_retries_set
      config.with_sync_redis do |conn|
        prn_retries_set(conn)
      end
    end

    def prune_scheduled_set
      config.with_sync_redis do |conn|
        prn_scheduled_set(conn)
      end
    end

    def prune_all_queues
      config.with_sync_redis do |conn|
        prn_all_queues(conn)
      end
    end

    def prune_queue(queue_name)
      config.with_sync_redis do |conn|
        conn.call('DEL', "#{config.queue_prefix}#{queue_name}")
      end
    end

    def unforsed_prune_outdated_processes_data
      return unless config.with_sync_redis do |conn| 
        conn.call('SET', CLEANUP_FLAG, '1', update: false, ex: 60)
      end

      prune_outdated_processes_data
    end

    # sometimes cleans valid processes :'(
    def prune_outdated_processes_data
      to_prune = []
      config.with_sync_redis do |conn|
        processes_hash = conn.call('HGETALL', config.processes_hash)
        stats_keys = conn.call('SCAN', '0', 'MATCH', "#{config.stats_prefix}*").last
        
        processes_hash.each do |k, v|
          process_data = JSON.parse(v)
          if process_data['stats_enabled'] && !stats_keys.include?("#{config.stats_prefix}#{k}")
            to_prune << k
          end
        end

        unless to_prune.empty?
          conn.call('HDEL', config.processes_hash, *to_prune)
          config.logger.warn('Pruned outdated processes') { to_prune }
        end
      end

      to_prune
    end

    def prune_all_unmonitored_processes
      config.with_sync_redis do |conn|
        processes_hash = Hash[*conn.call('HGETALL', config.processes_hash)]
        processes_hash.each do |k, v|
          process_data = JSON.parse(v)
          if !process_data['stats_enabled']
            prune_process(k)
          end
        end
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
      queues = conn.call('SCAN', '0', 'MATCH', "#{config.queue_prefix}*").last
      conn.call('DEL', *queues) unless queues.empty?
    end

    def prn_all_processes(conn)
      conn.call('DEL', config.processes_hash)
    end

    def prn_failures_counter(conn)
      conn.call('DEL', Jiggler::Stats::Monitor::FAILURES_COUNTER)
    end

    def prn_processed_counter(conn)
      conn.call('DEL', Jiggler::Stats::Monitor::PROCESSED_COUNTER)
    end
  end
end
