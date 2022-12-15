# frozen_string_literal: true

module Jiggler
  module Stats
    class Collection
      attr_reader :uuid, :data

      def initialize(uuid)
        @uuid = uuid
        @data = {
          processed: 0,
          failures: 0,
          current_jobs: {}
        }
      end
    end
  end
end
