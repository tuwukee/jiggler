# frozen_string_literal: true

require 'fc'

module Jiggler
  class AtLeastOnceFetcher < BasicFetcher
    TIMEOUT = 2.0 # 2 seconds of waiting for brpoplpush
    RESERVE_QUEUE_SUFFIX = 'in_progress_tasks'

    attr_reader :producers

    def initialize(config, collection)
      super
      @tasks_queue = FastContainers::PriorityQueue.new(:min)
      @condition = Async::Notification.new
      @consumers_queue = Queue.new
    end

    CurrentJob = Struct.new(:queue, :args, :reserve_queue, keyword_init: true) do
      def ack
        config.with_async_redis do |conn|
          conn.call('LREM', reserve_queue, args)
        end
      end
    end

    def start
      config.sorted_queues_data.each do |queue, data|
        safe_async("'Fetcher for #{queue}'") do
          list = data[:list]
          rlist = in_process_queue(list)
          loop do
            if @consumers_queue.num_waiting.zero? && !@done
              @condition.wait # supposed to block here until consumers notify
            end
            break if @done

            args = config.with_async_redis do |conn|
              conn.blocking_call(false, 'BRPOPLPUSH', list, rlist, TIMEOUT)
            end
            # no requeue logic rn as we expect monitor to handle
            # in-process-tasks list for this process
            break if @done

            next if args.nil? 

            @tasks_queue.push(job(list, args, rlist), data[:priority]) 
            @consumers_queue.push('') # to unblock any waiting consumer
          end
        end
      end
    end

    def fetch
      @condition.signal
      closed = @consumers_queue.pop.nil?
      closed ? nil : @tasks_queue.pop
    end

    def suspend
      @done = true
      @condition.signal
      @consumers_queue.close # unblocks awaiting consumers
    end

    private

    def in_process_queue(queue)
      "#{queue}:#{RESERVE_QUEUE_SUFFIX}:#{collection.uuid}"
    end

    def job(queue, args, reserve_queue)
      CurrentJob.new(queue:, args:, reserve_queue:)
    end
  end
end
