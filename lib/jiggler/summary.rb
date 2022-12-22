# frozen_string_literal: true

module Jiggler
  class Summary
    KEYS = %w[
      retry_jobs_count
      dead_jobs_count
      scheduled_jobs_count
      failures_count
      processed_count
      monitor_enabled
      processes
      queues
    ].freeze

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def self.all(config = Jiggler.config)
      new(config).all
    end

    def all
      summary = {}
      collected_data = config.with_sync_redis do |conn|
        data = conn.pipelined do |pipeline|
          pipeline.call('ZCARD', config.retries_set)
          pipeline.call('ZCARD', config.dead_set)
          pipeline.call('ZCARD', config.scheduled_set)
          pipeline.call('GET', Jiggler::Stats::Monitor::FAILURES_COUNTER)
          pipeline.call('GET', Jiggler::Stats::Monitor::PROCESSED_COUNTER)
          pipeline.call('GET', Jiggler::Stats::Monitor::MONITOR_FLAG)
        end
        [*data, fetch_and_format_processes(conn), fetch_and_format_queues(conn)]
      end
      KEYS.each_with_index do |key, index|
        val = collected_data[index]
        val = val.to_i if index <= 4 # counters
        summary[key] = val
      end
      summary
    end

    private

    def fetch_and_format_processes(conn)
      processes = conn.call('HGETALL', config.processes_hash)
      processes_data = {}

      collected_data = conn.pipelined do |pipeline|
        processes.each do |uuid, process_data|
          processes_data[uuid] = JSON.parse(process_data)
          if processes_data[uuid]['stats_enabled']
            pipeline.call('GET', "#{config.stats_prefix}#{uuid}")
          end
        end
      end
      
      processes.each do |uuid, _|
        if processes_data[uuid]['stats_enabled']
          stats_data = collected_data.shift
          processes_data[uuid].merge!(JSON.parse(stats_data)) if stats_data
        end
        processes_data[uuid]['current_jobs'] ||= []
      end
      processes_data
    end

    def fetch_and_format_queues(conn)
      lists = conn.call('SCAN', '0', 'MATCH', "#{config.queue_prefix}*").last
      lists_data = {}

      collected_data = conn.pipelined do |pipeline|
        lists.each do |list|
          pipeline.call('LLEN', list)
        end
      end
      lists.each_with_index do |list, index|
        lists_data[list.split(':').last] = collected_data[index]
      end
      lists_data
    end
  end
end
