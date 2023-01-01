# frozen_string_literal: true

module Jiggler
  module Stats
    class Collection
      attr_reader :uuid, :data, :job_classes

      def initialize(uuid)
        @uuid = uuid
        @data = {
          processed: 0,
          failures: 0,
          current_jobs: {}
        }
        @job_classes = {}
      end

      def incr_processed
        @data[:processed] += 1
      end

      def incr_failures
        @data[:failures] += 1
      end

      def fetch_job_class(name)
        @job_classes[name] ||= constantize(name) 
      end

      private

      def constantize(str)
        return Object.const_get(str) unless str.include?('::')
  
        names = str.split('::')
        names.shift if names.empty? || names.first.empty?
  
        names.inject(Object) do |constant, name|
          constant.const_get(name, false)
        end
      rescue => err
        raise UnknownJobError, 'Cannot initialize job'
      end
    end
  end
end
