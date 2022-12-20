# frozen_string_literal: true

module Jiggler
  class Cleaner
    CLEANUP_FLAG = "jiggler:flag:cleanup"
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def prune_all
      config.with_redis(async: false) do |conn|
        conn.pipeline do |pipeline|
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
      config.with_redis(async: false) do |conn|
        prn_failures_counter(conn)
      end
    end

    def prune_processed_counter
      config.with_redis(async: false) do |conn|
        prn_processed_counter(conn)
      end
    end

    def prune_all_processes
      config.with_redis(async: false) do |conn|
        prn_all_processes(conn)
      end
    end

    def prune_process(uuid)
      config.with_redis(async: false) do |conn|
        conn.call("hdel", config.processes_hash, uuid)
      end
    end

    def prune_dead_set
      config.with_redis(async: false) do |conn|
        prn_dead_set(conn)
      end
    end

    def prune_retries_set
      config.with_redis(async: false) do |conn|
        prn_retries_set(conn)
      end
    end

    def prune_scheduled_set
      config.with_redis(async: false) do |conn|
        prn_scheduled_set(conn)
      end
    end

    def prune_all_queues
      config.with_redis(async: false) do |conn|
        prn_all_queues(conn)
      end
    end

    def prune_queue(queue_name)
      config.with_redis(async: false) do |conn|
        conn.call("del", "#{config.queue_prefix}#{queue_name}")
      end
    end

    def unforsed_prune_outdated_processes_data
      return unless config.with_redis(async: false) { |conn| conn.set(CLEANUP_FLAG, "1", update: false, seconds: 60) }

      prune_outdated_processes_data
    end

    def prune_outdated_processes_data
      to_prune = []
      config.with_redis(async: false) do |conn|
        processes_hash = Hash[*conn.call("hgetall", config.processes_hash)]
        stats_keys = conn.call("scan", "0", "match", "#{config.stats_prefix}*").last
        
        processes_hash.each do |k, v|
          process_data = JSON.parse(v)
          if process_data["stats_enabled"] && !stats_keys.include?("#{config.stats_prefix}#{k}")
            to_prune << k
          end
        end

        unless to_prune.empty?
          conn.call("hdel", config.processes_hash, *to_prune)
          config.logger.info("Prune outdated processes") { to_prune }
        end
      end

      to_prune
    end

    def prune_all_unmonitored_processes
      config.with_redis(async: false) do |conn|
        processes_hash = Hash[*conn.call("hgetall", config.processes_hash)]
        processes_hash.each do |k, v|
          process_data = JSON.parse(v)
          if !process_data["stats_enabled"]
            prune_process(k)
          end
        end
      end
    end

    private

    def prn_retries_set(conn)
      conn.call("del", config.retries_set)
    end

    def prn_scheduled_set(conn)
      conn.call("del", config.scheduled_set)
    end

    def prn_dead_set(conn)
      conn.call("del", config.dead_set)
    end

    def prn_all_queues(conn)
      queues = conn.call("scan", "0", "match", "#{config.queue_prefix}*").last
      conn.call("del", *queues) unless queues.empty?
    end

    def prn_all_processes(conn)
      conn.call("del", config.processes_hash)
    end

    def prn_failures_counter(conn)
      conn.call("del", Jiggler::Stats::Monitor::FAILURES_COUNTER)
    end

    def prn_processed_counter(conn)
      conn.call("del", Jiggler::Stats::Monitor::PROCESSED_COUNTER)
    end
  end
end
