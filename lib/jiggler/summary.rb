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
      collected_data = config.client_redis_pool.acquire do |conn|
        data = conn.pipelined do |pipeline|
          pipeline.call('ZCARD', config.retries_set)
          pipeline.call('ZCARD', config.dead_set)
          pipeline.call('ZCARD', config.scheduled_set)
          pipeline.call('GET', config.failures_counter)
          pipeline.call('GET', config.processed_counter)
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
      config.client_redis_pool.acquire do |conn|
        conn.call('ZRANGE', config.retries_set, '+inf', '-inf', 'BYSCORE', 'REV', 'LIMIT', 0, num)
      end.map { |job| Oj.load(job, mode: :compat) }
    end

    def last_scheduled_jobs(num)
      config.client_redis_pool.acquire do |conn|
        conn.call('ZRANGE', config.scheduled_set, '+inf', '-inf', 'BYSCORE', 'REV', 'LIMIT', 0, num, 'WITHSCORES')
      end.map do |(job, score)|
        Oj.load(job).merge('scheduled_at' => score)
      end
    end

    def last_dead_jobs(num)
      config.client_redis_pool.acquire do |conn|
        conn.call('ZRANGE', config.dead_set, '+inf', '-inf', 'BYSCORE', 'REV', 'LIMIT', 0, num)
      end.map { |job| Oj.load(job, mode: :compat) }
    end

    private

    def fetch_processes(conn)
      # in case they keys were deleted/modified could return incorrect results
      conn.call('SCAN', '0', 'MATCH', config.process_scan_key).last
    end

    def fetch_and_format_processes(conn)
      fetch_processes(conn).reduce({}) do |acc, uuid|
        process_data = Oj.load(conn.call('GET', uuid), mode: :compat) || {}
        values = uuid.split(':')
        acc[uuid] = process_data.merge({
          'name' => values[0..2].join(':'),
          'concurrency' => values[3],
          'timeout' => values[4],
          'queues' => values[5],
          'poller_enabled' => values[6] == '1',
          'started_at' => values[7],
          'pid' => values[8]
        })
        acc[uuid]['hostname'] = values[9..-1].join(':')
        acc
      end
    end

    def fetch_and_format_queues(conn)
      lists = conn.call('SCAN', '0', 'MATCH', config.queue_scan_key).last
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
