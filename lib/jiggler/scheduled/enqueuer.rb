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

      def enqueue_jobs(sorted_sets = sets)
        @config.with_redis(async: false) do |conn|
          sorted_sets.each do |sorted_set|
            # Get next item in the queue with score (time to execute) <= now
            while !@done && (job_args = zpopbyscore(conn, keys: [sorted_set], argv: [Time.now.to_f.to_s]))
              push_job(job_args)
            end
          end
        end
      end

      def push_job(job_args)
        name = JSON.parse(job_args)["queue"] || @config.default_queue
        list_name = @config.queues_hash[name]
        if list_name.nil?
          logger.warn("Queue #{name} does not exist. Dropping job: #{job_args}")
        else
          logger.debug("Pushing job back to the queue: #{job_args}")
          @config.with_redis { |conn| conn.lpush(list_name, job_args) }
        end
      end
      
      def sets
        [@config.retries_set, @config.scheduled_set]
      end

      def terminate
        @done = true
      end

      private

      def zpopbyscore(conn, keys: nil, argv: nil)
        if @lua_zpopbyscore_sha.nil?
          @lua_zpopbyscore_sha = conn.call("SCRIPT", "LOAD", LUA_ZPOPBYSCORE)
        end
        res = conn.call("EVALSHA", @lua_zpopbyscore_sha, keys.length, *keys, *argv)
        res
      rescue Protocol::Redis::Error => e
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
