# frozen_string_literal: true

require "async"
require "json"

module Jiggler
  module Job
    attr_reader :name, :args

    module ClassMethods
      attr_reader :retries
      
      def perform_async(**args)
        new(**args).perform_async
      end

      def queue
        @queue || Jiggler::Config::DEFAULT_QUEUE
      end

      def job_options(queue: Jiggler::Config::DEFAULT_QUEUE, retries: 0)
        @queue = queue
        @retries = retries
      end
    end
    
    def self.included(base)
      base.extend(ClassMethods)
      
      base.class_exec do
        def initialize(**args)
          @name = self.class.name
          @args = args
        end
      end
    end

    def perform_async
      puts "perform async #{list_name}"
      Jiggler.redis { |conn| conn.lpush(list_name, job_args)  }
    end

    private

    def list_name
      "#{Jiggler.config.queue_prefix}#{self.class.queue}"
    end

    def job_args
      @job_args ||= { name: name, args: args, retries: self.class.retries }.to_json
    end
  end
end
