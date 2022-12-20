# frozen_string_literal: true

require "async"
require "json"

module Jiggler
  module Job
    module ClassMethods
      def enqueue(*args)
        Enqueuer.new(self, { async: async }).enqueue(*args)
      end

      def enqueue_in(seconds, *args)
        Enqueuer.new(self, { async: async }).enqueue_in(seconds, *args)
      end

      # MyJob.with_options(queue: "custom", retries: 3).enqueue(*args)
      def with_options(options)
        Enqueuer.new(self, options)
      end

      def queue
        @queue || Jiggler::Config::DEFAULT_QUEUE
      end

      def retry_queue
        @retry_queue || Jiggler::Config::DEFAULT_QUEUE
      end

      def retries
        @retries || 0
      end

      def async
        @async || false
      end

      def job_options(queue: Jiggler::Config::DEFAULT_QUEUE, retries: 0, retry_queue: nil, async: false)
        @queue = queue
        @retries = retries
        @retry_queue = retry_queue || queue
        @async = async
      end
    end
    class Enqueuer
      def initialize(klass, options)
        @options = options
        @klass = klass
      end

      def with_options(options)
        @options.merge(options)
        self
      end

      def enqueue(*args)
        config.with_redis(async: @options.fetch(:async, false)) do |conn|
          conn.lpush(list_name, job_args(args))
        end
      end

      def enqueue_in(seconds, *args)
        timestamp = Time.now.to_f + seconds
        config.with_redis(async: @options.fetch(:async, false)) do |conn| 
          conn.zadd(
            config.scheduled_set, 
            timestamp, 
            job_args(args)
          ) 
        end
      end

      def list_name
        "#{config.queue_prefix}#{@options[:queue] || @klass.queue}"
      end

      def job_args(raw_args)
        { name: @klass.name, args: raw_args, **job_options }.to_json
      end

      def job_options
        retries = @options[:retries] || @klass.retries
        jid = @options[:jid] || SecureRandom.hex(8)
        { retries: retries, jid: jid }
      end

      def config
        @config ||= Jiggler.config
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def enqueue(*args)
      Enqueuer.new(self.class, {}).enqueue(*args)
    end

    def enqueue_in(seconds, *args)
      Enqueuer.new(self.class, {}).enqueue_in(seconds, *args)
    end

    def perform(**args)
      raise #{self.class} must implement 'perform' method"
    end
  end
end
