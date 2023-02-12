# frozen_string_literal: true

module Jiggler
  module Stats
    class Collection
      attr_reader :uuid, :identity, :data

      def initialize(uuid, identity)
        @uuid = uuid
        @identity = identity
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
