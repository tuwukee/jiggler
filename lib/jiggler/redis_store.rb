# frozen_string_literal: true

module Jiggler
  class RedisStore
    :config

    def initialize(options = {})
      @redis_config = RedisClient.new(options[:redis_url])
    end

    def client
      @redis_config.new_client
    end
  end
end
