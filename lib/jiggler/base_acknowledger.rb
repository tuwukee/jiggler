# frozen_string_literal: true

module Jiggler
  class BaseAcknowledger
    include Support::Helper

    def initialize(config)
      @config = config
    end
  end
end
