# frozen_string_literal: true

module Jiggler
  class RedisStore
    :config

    def initialize(options = {})
      @options = options
      @redis_config = RedisClient.config(url: options[:redis_url])
    end

    def pool
      Async::Pool::Controller.new(limit: options[:concurrency]).wrap do
        @redis_config.new_client
      end
    end
  end
end

module Jiggler
  class RedisClient < ::RedisClient
    def concurrency
      1
    end

    def viable?
      connected?
    end

    def closed?
      @raw_connection.nil?
    end

    def reusable?
      !@raw_connection.nil?
    end
  end
end
