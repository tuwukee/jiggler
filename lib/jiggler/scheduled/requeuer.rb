# frozen_string_literal: true

module Jiggler
  module Scheduled
    class Requeuer
      include Support::Helper

      def initialize(config)
        @config = config
        @done = false
        @tid = tid
      end

      def handle_stale
        requeue_data.each do |(rqueue, queue, _)|
          @config.with_async_redis do |conn|
            loop do
              return if @done
              # reprocessing is prioritised so we push at the right side
              break if conn.call('LMOVE', rqueue, queue, 'RIGHT', 'RIGHT').nil?
            end
          end
        end
      rescue => err
        log_error_short(err, context: '\'Requeuing jobs error\'', tid: @tid)
      end

      def terminate
        @done = true
      end

      private

      def requeue_data
        grouped_queues = in_progress_queues.map do |queue|
          [queue, *queue.split(":#{AtLeastOnce::Fetcher::RESERVE_QUEUE_SUFFIX}:")]
        end.group_by(&:last)
        # returns [[queue_in_progress, queue, uuid]] for non-running processes
        grouped_queues.except(*running_processes_uuid).values.flatten(1)
      end

      def running_processes_uuid
        scan_all(@config.process_scan_key).map do |process|
          process.split(':')[2]
        end
      end

      def in_progress_queues
        scan_all(in_progress_wildcard)
      end

      def in_progress_wildcard
        "*#{AtLeastOnce::Fetcher::RESERVE_QUEUE_SUFFIX}*"
      end
    end
  end
end
