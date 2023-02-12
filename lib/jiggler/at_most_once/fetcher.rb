# frozen_string_literal: true

module Jiggler
  module AtMostOnce
    class Fetcher < BaseFetcher
      TIMEOUT = 2.0 # 2 seconds of waiting for brpop

      CurrentJob = Struct.new(:queue, :args)

      def start
        # noop, we just block directly during the fetch
      end

      def fetch
        return :done if @done

        q, args = config.with_sync_redis do |conn|
          conn.blocking_call(false, 'BRPOP', *config.sorted_lists, TIMEOUT)
        end

        if @done
          requeue(q, args) unless q.nil?
          return :done
        end

        job(q, args) unless q.nil?
      end

      def suspend
        @done = true
      end

      private

      def requeue(queue, args)
        config.with_sync_redis do |conn|
          conn.call('RPUSH', queue, args)
        end
      end

      def job(queue, args)
        CurrentJob.new(queue, args)
      end
    end
  end
end
