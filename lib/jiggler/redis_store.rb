# frozen_string_literal: true

require 'redis_client'
require 'async/pool'

module Jiggler
  class RedisStore
    def initialize(options = {})
      @options = options
      @redis_config = RedisClient.config(url: options[:redis_url], timeout: nil)
    end

    def pool      
      @options[:async] ? async_pool : sync_pool
    end

    def async_pool
      Async::Pool::Controller.wrap(limit: @options[:concurrency]) do
        @redis_config.new_client
      end
    end

    def sync_pool
      # use connection_pool from redis-store dependency
      pool = ConnectionPool.new(size: @options[:concurrency], timeout: 2.0) do 
        @redis_config.new_client
      end
      def pool.acquire(&block)
        with(&block)
      end
      pool
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
