# frozen_string_literal: true

require "async"
require "json"

module Jiggler
  module Job
    attr_reader :name, :args

    module ClassMethods
      def perform_async(**args)
        new(**args).perform_async
      end

      def queue
        @queue || Jiggler.default_job_options[:default_queue]
      end

      def job_options(queue:)
        @queue = queue
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
      Async do
        puts list_name
        Jiggler.redis_client.lpush(list_name, job_args) 
      end
    end

    private

    def list_name
      "#{Jiggler.list_prefix}#{self.class.queue}"
    end

    def job_args
      @job_args ||= { name: name, args: args }.to_json
    end
  end
end
