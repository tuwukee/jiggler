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
      end

      def incr_processed
        @data[:processed] += 1
      end

      def incr_failures
        @data[:failures] += 1
      end
    end
  end
end
