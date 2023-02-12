# frozen_string_literal: true

require 'forwardable'
require 'logger'

module Jiggler
  class Config
    extend Forwardable

    DEFAULT_QUEUE = 'default'
    QUEUE_PREFIX = 'jiggler:list:'
    SERVER_PREFIX = 'jiggler:svr:'
    RETRIES_SET = 'jiggler:set:retries'
    SCHEDULED_SET = 'jiggler:set:scheduled'
    DEAD_SET = 'jiggler:set:dead'
    PROCESSED_COUNTER = 'jiggler:stats:processed_counter'
    FAILURES_COUNTER = 'jiggler:stats:failures_counter'

    DEFAULTS = {
      require: nil,
      environment: 'development',
      concurrency: 10,
      timeout: 25,
      max_dead_jobs: 10_000,
      stats_interval: 10,
      poller_enabled: true,
      poll_interval: 5,
      in_process_interval: 10,
      dead_timeout: 180 * 24 * 60 * 60, # 6 months in seconds
      # client settings
      client_concurrency: 10,
      client_redis_pool: nil,
      fetchers_concurrency: 1,
      client_async: false,
      guaranteed_execution: true
    }

    def initialize(options = {})
      @options = DEFAULTS.merge(options)
      @options[:redis_url] = ENV['REDIS_URL'] if @options[:redis_url].nil? && ENV['REDIS_URL']
      @options[:queues] ||= [DEFAULT_QUEUE]
      @directory = {}
    end

    def queue_prefix
      QUEUE_PREFIX
    end

    def retries_set
      RETRIES_SET
    end

    def scheduled_set
      SCHEDULED_SET
    end

    def dead_set
      DEAD_SET
    end

    def default_queue
      DEFAULT_QUEUE
    end

    # jiggler main process prefix
    def server_prefix
      SERVER_PREFIX
    end

    def processed_counter
      PROCESSED_COUNTER
    end

    def failures_counter
      FAILURES_COUNTER
    end

    def process_scan_key
      @process_scan_key ||= "#{server_prefix}*"
    end

    def queue_scan_key
      @queue_scan_key ||= "#{queue_prefix}*"
    end

    def queues_data
      @queues_data ||= begin
        queues = {}

        @options[:queues].each do |queue|
          name, priority = queue
          # by default all queues have the same priority
          priority ||= 0

          queues[name] = {
            priority: priority,
            # list is a redis list key for a queue
            list: "#{QUEUE_PREFIX}#{name}",
          }
        end
        
        queues
      end
    end
    
    # sort in descending order (higher priority first)
    def sorted_queues_data
      @sorted_queues_data ||= queues_data.sort_by { |_, v| -v[:priority] }
    end
    
    def sorted_lists
      @sorted_lists ||= sorted_queues_data.map { |_, v| v[:list] }
    end

    def sorted_queues
      @sorted_queues ||= sorted_queues_data.map { |k, _| k }
    end

    def with_async_redis
      Async do
        redis_pool.acquire do |conn|
          yield conn
        end
      end
    end

    def with_sync_redis
      Sync do
        redis_pool.acquire do |conn|
          yield conn
        end
      end
    end

    def redis_options
      @redis_options ||= begin
        opts = @options.slice(
          :concurrency,
          :redis_url
        )

        if @options[:guaranteed_execution]
          # for acknowledgers
          opts[:concurrency] *= 2
          # for queue fetchers
          opts[:concurrency] += @options[:fetchers_concurrency] * sorted_queues.count
          # extra poller task to cleanup leftover in-process queues
          opts[:concurrency] += 1
        end

        opts[:concurrency] += 2 # monitor + safety margin
        opts[:concurrency] += 1 if @options[:poller_enabled]
        opts[:async] = true

        opts
      end
    end

    def client_redis_options
      @client_redis_options ||= begin
        opts = @options.slice(
          :redis_url,
          :client_redis_pool
        )

        opts[:concurrency] = @options[:client_concurrency]
        opts[:async] = @options[:client_async]
        opts
      end
    end

    def redis_pool
      @redis_pool ||= Jiggler::RedisStore.new(redis_options).pool
    end

    def client_redis_pool
      @client_redis_pool ||= begin
        @options[:client_redis_pool] || Jiggler::RedisStore.new(client_redis_options).pool
      end
    end

    def client_redis_pool=(new_pool)
      @client_redis_pool = new_pool
    end

    def cleaner
      @cleaner ||= Jiggler::Cleaner.new(self)
    end

    def summary
      @summary ||= Jiggler::Summary.new(self)
    end

    def logger=(new_logger)
      @logger = new_logger
    end

    def logger
      @logger ||= ::Logger.new(STDOUT, level: :info)
    end
    
    def_delegators :@options, :[], :[]=, :fetch, :key?, :has_key?, :merge!, :delete, :slice
  end
end
