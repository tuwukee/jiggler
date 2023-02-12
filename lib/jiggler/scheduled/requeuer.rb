# frozen_string_literal: true

module Jiggler
  module Scheduled
    class Requeuer
      include Support::Helper

      def initialize(config)
        @config = config
        @done = false
        @lua_zpopbyscore_sha = nil
        @tid = tid
      end

      def enqueue_jobs
        @config.with_async_redis do |conn|
          sorted_sets.each do |sorted_set|
            # Get next item in the queue with score (time to execute) <= now
            job_args = zpopbyscore(conn, key: sorted_set, argv: Time.now.to_f.to_s)
            while !@done && job_args
              push_job(conn, job_args)
              job_args = zpopbyscore(conn, key: sorted_set, argv: Time.now.to_f.to_s)
            end
          end
        rescue => err
          log_error_short(err, context: '\'Enqueuing jobs error\'', tid: @tid)
        end
      end

      def terminate
        @done = true
      end

      def push_job(conn, job_args)
        name = Oj.load(job_args, mode: :compat)['queue'] || @config.default_queue
        list_name = "#{@config.queue_prefix}#{name}"
        # logger.debug('Poller Enqueuer') { "Pushing #{job_args} to #{list_name}" }
        conn.call('LPUSH', list_name, job_args)
      rescue => err
        log_error_short(
          err, { 
            context: '\'Pushing scheduled job error\'', 
            tid: @tid,
            job_args: job_args,
            queue: list_name
          }
        )
      end

      private
      
      def sorted_sets
        @sorted_sets ||= [@config.retries_set, @config.scheduled_set].freeze
      end

      def zpopbyscore(conn, key: nil, argv: nil)
        if @lua_zpopbyscore_sha.nil?
          @lua_zpopbyscore_sha = conn.call('SCRIPT', 'LOAD', LUA_ZPOPBYSCORE)
        end
        conn.call('EVALSHA', @lua_zpopbyscore_sha, 1, key, argv)
      rescue RedisClient::CommandError => e
        raise unless e.message.start_with?('NOSCRIPT')

        @lua_zpopbyscore_sha = nil
        retry
      end     
    end
  end
end
