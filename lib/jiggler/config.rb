# frozen_string_literal: true

require "forwardable"
require "logger"
require_relative "./redis_store"

module Jiggler
  class Config
    extend Forwardable

    DEFAULT_QUEUE = "default"
    QUEUE_PREFIX = "jiggler:list:"
    PROCESSES_HASH = "jiggler:hash:processes"
    RETRIES_SET = "jiggler:set:retries"
    SCHEDULED_SET = "jiggler:set:scheduled"
    DEAD_SET = "jiggler:set:dead"

    DEFAULTS = {
      boot_app: true,
      require: ".",
      environment: nil,
      concurrency: 5,
      timeout: 25,
      error_handlers: [],
      death_handlers: [],
      max_dead_jobs: 10_000,
      poll_interval_average: nil,
      average_scheduled_poll_interval: 5,
      dead_timeout_in_seconds: 180 * 24 * 60 * 60, # 6 months
    }

    ERROR_HANDLER = ->(ex, ctx, cfg = Jiggler.config) {
      l = cfg.logger
      l.warn(JSON.generate(ctx)) unless ctx.empty?
      l.warn("#{ex.class.name}: #{ex.message}")
      l.warn(ex.backtrace.join("\n")) unless ex.backtrace.nil?
    }

    def initialize(options = {})
      @options = DEFAULTS.merge(options)
      @options[:error_handlers] << ERROR_HANDLER if @options[:error_handlers].empty?
      @options[:redis_url] = ENV["REDIS_URL"] if @options[:redis_url].nil? && ENV["REDIS_URL"]
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

    def prefixed_queues
      @prefixed_queues ||= @options[:queues].map { |name| "#{QUEUE_PREFIX}#{name}" }
    end

    def with_redis(async: true)
      wrapper = async ? :Async : :Sync
      Kernel.public_send(wrapper) do
        yield redis
      end
    end

    def redis_options
      @redis_options ||= @options.slice(:concurrency, :redis_url, :cert, :key)
    end

    def redis
      @redis ||= Jiggler::RedisStore.new(redis_options).client
    end

    def logger=(new_logger)
      @logger = new_logger
    end

    def logger
      @logger = ::Logger.new(STDOUT)
    end

    def handle_exception(ex, ctx = {})
      if @options[:error_handlers].size == 0
        logger.error("No error handlers configured")
        logger.error(ex)
      end
      ctx[:_config] = self
      @options[:error_handlers].each do |handler|
        handler.call(ex, ctx)
      rescue => err
        logger.error(err)
        logger.error(err.backtrace.join("\n")) unless e.backtrace.nil?
      end
    end
    
    def_delegators :@options, :[], :[]=, :fetch, :key?, :has_key?, :merge!, :delete, :slice
  end
end
