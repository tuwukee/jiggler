# frozen_string_literal: true

# The Poller checks Redis every N seconds for jobs in the retry or scheduled
# set have passed their timestamp and should be enqueued.
module Jiggler
  module Scheduled    
    class Poller
      include Support::Component
      include Support::Cleaner

      INITIAL_WAIT = 10

      def initialize(config)
        @config = config
        @enqueuer = Jiggler::Scheduled::Enqueuer.new(config)
        @done = false
        @job = nil
        @count_calls = 0
        @condition = Async::Condition.new
      end

      def terminate
        @done = true
        @enqueuer.terminate

        Async do
          @condition.signal
          @job&.wait
        end
      end

      def start
        @job = safe_async("Poller") do
          initial_wait
          until @done
            enqueue
            wait unless @done
          end
        end
      end

      def enqueue
        @enqueuer.enqueue_jobs
      rescue => ex
        handle_exception(
          ex, { context: "'Error while enqueueing jobs'", tid: tid }
        )
      end

      private

      def wait
        Async(transient: true) do
          sleep(random_poll_interval)
          @condition.signal
        end
        @condition.wait
      rescue => ex
        handle_exception(
          ex, { context: "'Error while waiting for scheduled jobs'", tid: tid }
        )
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

      def process_count
        pcount = redis(async: false) { |conn| conn.call("hlen", config.processes_hash) }
        pcount = 1 if pcount == 0
        pcount
      end

      def cleanup
        prune_outdated_processes_data(config.processes_hash)
      end

      def initial_wait
        total = INITIAL_WAIT + (5 * rand)

        Async(transient: true) do
          sleep(total)
          @condition.signal
        end
        @condition.wait
      ensure
        cleanup
      end
    end
  end
end
