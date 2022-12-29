# frozen_string_literal: true

module Jiggler
  class Summary
    KEYS = %w[
      retry_jobs_count
      dead_jobs_count
      scheduled_jobs_count
      failures_count
      processed_count
      processes
      queues
    ].freeze

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def all
      summary = {}
      collected_data = config.redis_pool.acquire do |conn|
        data = conn.pipelined do |pipeline|
          pipeline.call('ZCARD', config.retries_set)
          pipeline.call('ZCARD', config.dead_set)
          pipeline.call('ZCARD', config.scheduled_set)
          pipeline.call('GET', Jiggler::Stats::Monitor::FAILURES_COUNTER)
          pipeline.call('GET', Jiggler::Stats::Monitor::PROCESSED_COUNTER)
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

    def last_retry_jobs(num)
      config.redis_pool.acquire do |conn|
        conn.call('ZRANGE', config.retries_set, '+inf', '-inf', 'BYSCORE', 'REV', 'LIMIT', 0, num)
      end.map { |job| JSON.parse(job) }
    end

    def last_scheduled_jobs(num)
      config.redis_pool.acquire do |conn|
        conn.call('ZRANGE', config.scheduled_set, '+inf', '-inf', 'BYSCORE', 'REV', 'LIMIT', 0, num, 'WITHSCORES')
      end.map do |(job, score)|
        JSON.parse(job).merge('scheduled_at' => score)
      end
    end

    def last_dead_jobs(num)
      config.redis_pool.acquire do |conn|
        conn.call('ZRANGE', config.dead_set, '+inf', '-inf', 'BYSCORE', 'REV', 'LIMIT', 0, num)
      end.map { |job| JSON.parse(job) }
    end

    private

    def fetch_and_format_processes(conn)
      processes = conn.call('HGETALL', config.processes_hash)
      processes_data = {}

      collected_data = conn.pipelined do |pipeline|
        processes.each do |uuid, process_data|
          processes_data[uuid] = JSON.parse(process_data)
          pipeline.call('GET', "#{config.stats_prefix}#{uuid}")
        end
      end
      
      processes.each do |uuid, _|
        stats_data = collected_data.shift
        processes_data[uuid].merge!(JSON.parse(stats_data)) if stats_data
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
