# frozen_string_literal: true

require 'forwardable'
require 'logger'

module Jiggler
  class Config
    extend Forwardable

    DEFAULT_QUEUE = 'default'
    QUEUE_PREFIX = 'jiggler:list:'
    PROCESSES_HASH = 'jiggler:hash:processes'
    STATS_PREFIX = 'jiggler:stats:'
    RETRIES_SET = 'jiggler:set:retries'
    SCHEDULED_SET = 'jiggler:set:scheduled'
    DEAD_SET = 'jiggler:set:dead'

    DEFAULTS = {
      require: nil,
      environment: 'development',
      concurrency: 10,
      timeout: 25,
      max_dead_jobs: 10_000,
      stats_interval: 10,
      poller_enabled: true,
      poll_interval: 5,
      dead_timeout: 180 * 24 * 60 * 60, # 6 months in seconds
      redis_pool: nil,
      redis_mode: :sync # :async or :sync. :sync is used on default for client connections
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

    def processes_hash
      PROCESSES_HASH
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

    def stats_prefix
      STATS_PREFIX
    end

    def default_queue
      DEFAULT_QUEUE
    end

    def prefixed_queues
      @prefixed_queues ||= @options[:queues].map do |name| 
        "#{QUEUE_PREFIX}#{name}" 
      end
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

    def with_redis(async: true)
      wrapper = async ? :Async : :Sync
      Kernel.public_send(wrapper) do
        redis_pool.acquire do |conn|
          yield conn
        end 
      end
    end

    def redis_options
      @redis_options ||= begin
        opts = @options.slice(
          :concurrency,
          :redis_url,
          :redis_pool,
          :redis_mode
        )
        if Jiggler.server?
          opts[:concurrency] += 3 # monitor (1) + safity margin (2)
          opts[:concurrency] += 2 if @options[:poller_enabled] # poller uses 2 fibers
          opts[:redis_mode] = :async
        end
        opts
      end
    end

    def redis_pool
      @redis_pool ||= Jiggler::RedisStore.new(redis_options).pool
    end

    def cleaner
      @cleaner ||= Jiggler::Cleaner.new(self)
    end

    def logger=(new_logger)
      @logger = new_logger
    end

    def logger
      @logger ||= ::Logger.new(STDOUT, level: :info)
    end

    def handle_exception(ex, ctx = {}, raise_ex: false)
      err_context = ctx.compact.map { |k, v| "#{k}=#{v}" }.join(' ')
      logger.error("error_message='#{ex.message}' #{err_context}")
      logger.error(ex.backtrace.first(12).join("\n")) unless ex.backtrace.nil?
      raise ex if raise_ex
    end
    
    def_delegators :@options, :[], :[]=, :fetch, :key?, :has_key?, :merge!, :delete, :slice
  end
end
