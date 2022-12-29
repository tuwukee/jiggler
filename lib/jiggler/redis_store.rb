# frozen_string_literal: true

require 'redis_client'
require 'async/pool'

module Jiggler
  class RedisStore
    def initialize(options = {})
      @options = options
    end

    def pool
      return @options[:redis_pool] if @options[:redis_pool]
      
      if @options[:redis_mode] == :async
        async_pool
      else
        sync_pool
      end
    end

    def async_pool
      @async_pool ||= begin
        config = RedisClient.config(url: @options[:redis_url], timeout: nil)
        Async::Pool::Controller.wrap(limit: @options[:concurrency]) do
          config.new_client
        end
      end
    end

    def sync_pool
      # use connection_pool from redis-store dependency
      @sync_pool ||= begin
        config = RedisClient.config(url: @options[:redis_url])
        pool = config.new_pool(size: @options[:conrurrency])
        def pool.acquire(&block)
          with(&block)
        end
        pool
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
