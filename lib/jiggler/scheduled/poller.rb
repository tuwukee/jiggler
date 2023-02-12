# frozen_string_literal: true

# The Poller checks Redis every N seconds for jobs in the retry or scheduled
# set have passed their timestamp and should be enqueued.
module Jiggler
  module Scheduled    
    class Poller
      include Support::Helper

      INITIAL_WAIT = 5

      def initialize(config)
        @config = config
        @enqueuer = Jiggler::Scheduled::Enqueuer.new(config)
        @requeuer = Jiggler::Scheduled::Requeuer.new(config)
        @done = false
        @job = nil
        @count_calls = 0
        @condition = Async::Condition.new
      end

      def terminate
        @done = true
        @enqueuer.terminate
        @requeuer.terminate

        Async do
          @condition.signal
          @job&.wait
        end
      end

      def start
        @job = Async do
          @tid = tid
          initial_wait
          safe_async('Poller') do
            until @done
              enqueue
              wait unless @done
            end
          end
          safe_async('Requeuer') do
            until @done
              handle_stale_in_process_queues
              wait(in_process_interval) unless @done
            end
          end
        end
      end

      def enqueue
        # logger.warn('Poller runs')
        @enqueuer.enqueue_jobs
      end

      def handle_stale_in_process_queues
        @requeuer.handle_stale
      end

      private

      def wait(interval = random_poll_interval)
        Async(transient: true) do
          sleep(timeout)
          @condition.signal
        end
        @condition.wait
      end

      def in_process_interval
        @config[:in_process_interval] * rand
      end

      def random_poll_interval
        count = process_count
        interval = @config[:poll_interval] 

        if count < 10
          interval * rand + interval.to_f / 2
        else
          interval * rand
        end
      end

      def fetch_count
        scan_all(@config.process_scan_key).size
      rescue => err
        log_error_short(err, { context: '\'Poller getting processes error\'', tid: @tid })
        1
      end

      def process_count
        count = fetch_count
        count = 1 if count.zero?
        count
      end

      # wait a random amount of time so in case of multiple processes 
      # their pollers won't be synchronized
      def initial_wait
        total = INITIAL_WAIT + (12 * rand)

        # in case of an early exit skip the initial wait
        Async(transient: true) do
          sleep(total)
          @condition.signal
        end
        @condition.wait
      end
    end
  end
end
