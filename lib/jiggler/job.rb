# frozen_string_literal: true

module Jiggler
  module Job
    module ClassMethods
      def enqueue(*args)
        Enqueuer.new(self).enqueue(*args)
      end

      def enqueue_in(seconds, *args)
        Enqueuer.new(self).enqueue_in(seconds, *args)
      end

      # MyJob.with_options(queue: 'custom', retries: 3).enqueue(*args)
      def with_options(options)
        Enqueuer.new(self, options)
      end

      def enqueue_bulk(args_arr)
        Enqueuer.new(self).enqueue_bulk(args_arr)
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

      def job_options(queue: nil, retries: nil, retry_queue: nil)
        @queue = queue || Jiggler::Config::DEFAULT_QUEUE
        @retries = retries || 0
        @retry_queue = retry_queue || queue
      end
    end

    class Enqueuer
      def initialize(klass, options = {})
        @options = options
        @klass = klass
      end

      def with_options(options)
        @options.merge(options)
        self
      end

      def enqueue(*args)
        Jiggler.config.redis_pool.acquire do |conn|
          conn.call('LPUSH', list_name, job_args(args))
        end
      end

      def enqueue_bulk(args_arr)
        Jiggler.config.redis_pool.acquire do |conn|
          conn.pipelined do |pipeline|
            args_arr.each do |args|
              pipeline.call('LPUSH', list_name, job_args(args))
            end
          end
        end
      end

      def enqueue_in(seconds, *args)
        timestamp = Time.now.to_f + seconds
        Jiggler.config.redis_pool.acquire do |conn|
          conn.call(
            'ZADD',
            config.scheduled_set, 
            timestamp, 
            job_args(args)
          )
        end
      end

      def list_name
        "#{config.queue_prefix}#{@options.fetch(:queue, @klass.queue)}"
      end

      def job_args(raw_args)
        JSON.generate({ name: @klass.name, args: raw_args, **job_options })
      end

      def job_options
        retries = @options.fetch(:retries, @klass.retries)
        jid = @options.fetch(:jid, SecureRandom.hex(8))
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
      Enqueuer.new(self.class).enqueue(*args)
    end

    def enqueue_in(seconds, *args)
      Enqueuer.new(self.class).enqueue_in(seconds, *args)
    end

    def perform(**args)
      raise "#{self.class} must implement 'perform' method"
    end
  end
end
