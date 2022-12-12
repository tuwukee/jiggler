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
      environment: "development",
      concurrency: 5,
      timeout: 25,
      max_dead_jobs: 10_000,
      poll_interval: 5,
      dead_timeout: 180 * 24 * 60 * 60, # 6 months in seconds
    }

    def initialize(options = {})
      @options = DEFAULTS.merge(options)
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

    def queues_hash
      @queues_hash ||= @options[:queues].each_with_object({}) do |name, hash| 
        hash[name] = "#{QUEUE_PREFIX}#{name}" 
      end
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

    def handle_exception(ex, ctx = {}, raise_ex: false)
      err_context = ctx.select { |k, v| v }.map { |k, v| "#{k}=#{v}" }.join(" ")
      logger.error("#{ex.message} #{err_context}")
      logger.error(ex.backtrace.first(10).join("\n")) if !ex.backtrace.nil? || raise_ex == false
      raise ex if raise_ex
    end
    
    def_delegators :@options, :[], :[]=, :fetch, :key?, :has_key?, :merge!, :delete, :slice
  end
end
