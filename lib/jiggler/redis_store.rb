# frozen_string_literal: true

require 'redis_client'
require 'async/pool'

module Jiggler
  class RedisStore
    def initialize(options = {})
      @options = options
      @redis_config = RedisClient.config(url: options[:redis_url])
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
      Async::Pool::Controller.wrap(limit: @options[:concurrency]) do
        @redis_config.new_client
      end
    end

    def sync_pool
      # use connection_pool from redis-store dependency
      pool = ConnectionPool.new(size: @options[:concurrency]) do 
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
