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
        @requeuer_condition = Async::Condition.new
        @enqueuer_condition = Async::Condition.new
      end

      def terminate
        @done = true
        @enqueuer.terminate
        @requeuer.terminate

        Async do
          @requeuer_condition.signal
          @enqueuer_condition.signal
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
              wait(@enqueuer_condition) unless @done
            end
          end
          safe_async('Requeuer') do
            until @done
              handle_stale_in_process_queues
              logger.debug('Executing requeuer')
              wait(@requeuer_condition, in_process_interval) unless @done
            end
          end if @config.at_least_once?
        end
      end

      def enqueue
        @enqueuer.enqueue_jobs
      end

      def handle_stale_in_process_queues
        @requeuer.handle_stale
      end

      private

      def wait(condition, interval = random_poll_interval)
        Async(transient: true) do
          sleep(interval)
          condition.signal
        end
        condition.wait
      end

      def in_process_interval
        # 60 to 120 seconds by default
        [@config[:in_process_interval] * rand, 60].max
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
        wait(@enqueuer_condition, INITIAL_WAIT + (12 * rand))
      end
    end
  end
end
