# frozen_string_literal: true

module Jiggler
  class AtMostOnceFetcher < BasicFetcher
    TIMEOUT = 2.0 # 2 seconds of waiting for brpop

    def initialize(config, collection)
      super
      @tasks_queue = Queue.new
      @condition = Async::Notification.new
    end

    CurrentJob = Struct.new(:queue, :args, keyword_init: true) do
      def ack
        # noop
      end
    end

    def start
      safe_async('Fetcher') do
        loop do
          if @tasks_queue.num_waiting.zero? && !@done
            @condition.wait # supposed to block here until consumers notify
          end
          break if @done

          q, args = config.with_async_redis do |conn|
            conn.blocking_call(false, 'BRPOP', *config.sorted_lists, TIMEOUT)
          end
          break if args.nil? && @done

          @done ? requeue(q, args) : @tasks_queue.push(job(q, args))
        end
      end
    end

    def fetch
      @condition.signal
      @tasks_queue.pop
    end

    def suspend
      @done = true
      @condition.signal
      @tasks_queue.close # unblocks awaiting consumers
    end

    private

    def requeue(queue, args)
      config.with_async_redis do |conn|
        conn.call('RPUSH', queue, args)
      end
    end

    def job(queue, args)
      CurrentJob.new(queue:, args:)
    end
  end
end
