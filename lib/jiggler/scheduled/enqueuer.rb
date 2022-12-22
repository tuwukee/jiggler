# frozen_string_literal: true

module Jiggler
  module Scheduled
    class Enqueuer
      LUA_ZPOPBYSCORE = <<~LUA
        local key, now = KEYS[1], ARGV[1]
        local jobs = redis.call("zrangebyscore", key, "-inf", now, "limit", 0, 1)
        if jobs[1] then
          redis.call("zrem", key, jobs[1])
          return jobs[1]
        end
      LUA

      def initialize(config)
        @config = config
        @done = false
        @lua_zpopbyscore_sha = nil
      end

      def enqueue_jobs
        @config.with_redis do |conn|
          sorted_sets.each do |sorted_set|
            # Get next item in the queue with score (time to execute) <= now
            job_args = zpopbyscore(conn, keys: [sorted_set], argv: [Time.now.to_f.to_s])
            while !@done && job_args
              push_job(conn, job_args)
              job_args = zpopbyscore(conn, keys: [sorted_set], argv: [Time.now.to_f.to_s])
            end
          end
        end
      end

      def terminate
        @done = true
      end

      def push_job(conn, job_args)
        name = JSON.parse(job_args)["queue"] || @config.default_queue
        list_name = "#{@config.queue_prefix}#{name}"
        logger.debug("Poller Enqueuer") { "Pushing #{job_args} to #{list_name}" }
        conn.call("LPUSH", list_name, job_args)
      rescue => err
        logger.error("Error while pushing #{job_args} to queue: #{err}")
      end

      private
      
      def sorted_sets
        @sorted_sets ||= [@config.retries_set, @config.scheduled_set].freeze
      end

      def zpopbyscore(conn, keys: nil, argv: nil)
        if @lua_zpopbyscore_sha.nil?
          @lua_zpopbyscore_sha = conn.call("SCRIPT", "LOAD", LUA_ZPOPBYSCORE)
        end
        conn.call("EVALSHA", @lua_zpopbyscore_sha, keys.length, *keys, *argv)
      rescue RedisClient::CommandError => e
        raise unless e.message.start_with?("NOSCRIPT")

        @lua_zpopbyscore_sha = nil
        retry
      end

      def logger
        @config.logger
      end      
    end
  end
end
