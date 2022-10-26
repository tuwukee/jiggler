# frozen_string_literal: true

require "forwardable"
require_relative "./redis_store"

module Jiggler
  # global configuration
  class Config
    extend Forwardable

    DEFAULT_QUEUE = "default"
    RETRY_QUEUE = "retry"
    PROCESSING_QUEUE = "processing"

    DEFAULTS = {
      labels: Set.new,
      require: ".",
      environment: nil,
      concurrency: 5,
      timeout: 25,
      poll_interval_average: nil,
      average_scheduled_poll_interval: 5,
      on_complex_arguments: :raise,
      error_handlers: [],
      death_handlers: [],
      lifecycle_events: {
        startup: [],
        quiet: [],
        shutdown: [],
        # triggers when we fire the first heartbeat on startup OR repairing a network partition
        heartbeat: [],
        # triggers on EVERY heartbeat call, every 10 seconds
        beat: []
      },
      dead_max_jobs: 10_000,
      dead_timeout_in_seconds: 180 * 24 * 60 * 60, # 6 months
      reloader: proc { |&block| block.call }
    }

    ERROR_HANDLER = ->(ex, ctx, cfg = Jiggler.default_config) {
      l = cfg.logger
      l.warn(JSON.generate(ctx)) unless ctx.empty?
      l.warn("#{ex.class.name}: #{ex.message}")
      l.warn(ex.backtrace.join("\n")) unless ex.backtrace.nil?
    }

    def initialize(options = {})
      @options = DEFAULTS.merge(options)
      @options[:error_handlers] << ERROR_HANDLER if @options[:error_handlers].empty?
      @directory = {}
      @redis_config = {}
    end

    def with_redis(async: true)
      wrapper = async ? :Async : :Sync
      Kernel.public_send(wrapper) do
        yield redis
      end
    end

    def redis_options
      @options.slice(:concurrency, :redis_url, :cert, :key)
    end

    def redis
      @redis ||= Jiggler::RedisStore.new.client(redis_options)
    end

    def logger=(new_logger)
      @logger = new_logger
    end

    def logger
      @logger = Logger.new(STDOUT)
    end

    def handle_exception(ex, ctx = {})
      if @options[:error_handlers].size == 0
        p ["!!!!!", ex]
      end
      ctx[:_config] = self
      @options[:error_handlers].each do |handler|
        handler.call(ex, ctx)
      rescue => e
        l = logger
        l.error "!!! ERROR HANDLER THREW AN ERROR !!!"
        l.error e
        l.error e.backtrace.join("\n") unless e.backtrace.nil?
      end
    end

    def_delegators :@options, :[], :[]=, :fetch, :key?, :has_key?, :merge!
  end
end
