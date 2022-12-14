# frozen_string_literal: true

require "async"
require "json"

module Jiggler
  module Job
    attr_reader :_args, :_jid

    module ClassMethods
      def perform_async(**args)
        new(**args).perform_async
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

      def job_options(queue: Jiggler::Config::DEFAULT_QUEUE, retries: 0, retry_queue: nil)
        @queue = queue
        @retries = retries
        @retry_queue = retry_queue || queue
      end
    end
    
    def self.included(base)
      base.extend(ClassMethods)
      
      base.class_exec do
        def initialize(**args)
          @_args = args
          @_jid = args["jid"] || SecureRandom.hex(8)
        end
      end
    end

    def perform_async
      Jiggler.redis { |conn| conn.lpush(list_name, job_args) }
    end

    private

    def list_name
      "#{Jiggler.config.queue_prefix}#{self.class.queue}"
    end

    def job_args
      @job_args ||= { name: self.class.name, args: _args, retries: self.class.retries }.to_json
    end
  end
end
