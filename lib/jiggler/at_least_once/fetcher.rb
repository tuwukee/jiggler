# frozen_string_literal: true

require 'fc'

module Jiggler
  module AtLeastOnce
    class Fetcher < BaseFetcher
      TIMEOUT = 2.0 # 2 seconds of waiting for brpoplpush
      RESERVE_QUEUE_SUFFIX = 'in_progress'

      attr_reader :producers

      def initialize(config, collection)
        super
        @tasks_queue = FastContainers::PriorityQueue.new(:min)
        @condition = Async::Notification.new
        @consumers_queue = Queue.new
      end

      CurrentJob = Struct.new(:queue, :args, :reserve_queue, :config, keyword_init: true) do
        def ack
          config.with_sync_redis do |conn|
            conn.call('LREM', reserve_queue, 1, args)
          end
        end
      end

      def start
        config.sorted_queues_data.each do |queue, data|
          config[:fetchers_concurrency].times do
            safe_async("'Fetcher for #{queue}'") do
              list = data[:list]
              rlist = in_process_queue(list)
              loop do
                # @consumers_queue.num_waiting may return 1 even if there are no :(
                if (@consumers_queue.num_waiting.zero? || @consumers_queue.size > @config[:concurrency]) && !@done
                  @condition.wait # supposed to block here until consumers notify
                end
                break if @done

                args = config.with_sync_redis do |conn|
                  conn.blocking_call(false, 'BRPOPLPUSH', list, rlist, TIMEOUT)
                end
                # no requeue logic rn as we expect monitor to handle
                # in-process-tasks list for this process
                break if @done

                next if args.nil? 

                @tasks_queue.push(job(list, args, rlist), data[:priority]) 
                @consumers_queue.push('') # to unblock any waiting consumer
              end
              logger.debug("Fetcher for #{queue} stopped")
            rescue Async::Stop
              logger.debug("Fetcher for #{queue} received stop signal")
            end
          end
        end
      end

      def fetch
        @condition.signal if signal?
        return :done if @consumers_queue.pop.nil?

        @tasks_queue.pop
      end

      def suspend
        logger.debug("Suspending the fetcher")
        @done = true
        @condition.signal
        @consumers_queue.close # unblocks awaiting consumers
      end

      private

      def queue_signaling_limit
        @queue_signaling_limit ||= [config[:concurrency] / 2, 1].max
      end

      def signal?
        @consumers_queue.size < config[:concurrency]
      end

      def in_process_queue(queue)
        "#{queue}:#{RESERVE_QUEUE_SUFFIX}:#{collection.uuid}"
      end

      def job(queue, args, reserve_queue)
        CurrentJob.new(queue:, args:, reserve_queue:, config:)
      end
    end
  end
end
