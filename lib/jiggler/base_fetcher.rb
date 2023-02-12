# frozen_string_literal: true

module Jiggler
  class BaseFetcher
    include Support::Helper

    attr_reader :config, :collection

    def initialize(config, collection)
      @config = config
      @collection = collection
    end
  end
end
