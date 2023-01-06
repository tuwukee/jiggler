# frozen_string_literal: true

require 'redis_client'

module Jiggler
  class RedisStore
    def initialize(options = {})
      @options = options
    end

    def pool      
      @options[:async] ? async_pool : sync_pool
    end

    def async_pool
      @async_pool ||= begin
        config = RedisClient.config(url: @options[:redis_url], timeout: nil)
        Polyphony::ResourcePool.new(limit: @options[:concurrency]) do
          config.new_client
        end
      end
    end

    def sync_pool
      @sync_pool ||= begin
        config = RedisClient.config(url: @options[:redis_url])
        config.new_pool(size: @options[:concurrency])
      end
    end
  end
end
