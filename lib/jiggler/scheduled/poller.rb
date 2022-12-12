# frozen_string_literal: true

require_relative "./enqueuer"

# The Poller checks Redis every N seconds for jobs in the retry or scheduled
# set have passed their timestamp and should be enqueued.
module Jiggler
  module Scheduled    
    class Poller
      include Component
      INITIAL_WAIT = 10
      CLEANUP_FLAG = "jiggler:flag:process_cleanup"

      def initialize(config)
        @config = config
        @enqueuer = Jiggler::Scheduled::Enqueuer.new(config)
        @done = false
        @job = nil
        @count_calls = 0
        @sleep_interval = nil
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
          sleep(@sleep_interval || random_poll_interval)
          @condition.signal
        end
        @condition.wait
      rescue => ex
        handle_exception(
          ex, { context: "'Error while waiting for scheduled jobs'", tid: tid }
        )
        sleep(5)
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
        pcount = redis(async: false) { |conn| conn.call("HLEN", Jiggler.config.processes_hash) }
        pcount = 1 if pcount == 0
        pcount
      end

      # TODO: Should be out of this class (?)
      def cleanup
        return 0 unless redis(async: false) { |conn| conn.set(CLEANUP_FLAG, "1", update: false, seconds: 60) }
        
        to_prune = []
        redis(async: false) do |conn|
          processes = conn.call("HGETALL", Jiggler.config.processes_hash)

          processes.each_slice(2) do |k, v| 
            heartbeat = JSON.parse(v)["heartbeat"].to_f
            if heartbeat < Time.now.to_i - 60.0 || heartbeat <= 0
              to_prune << k
            end
          end

          conn.call("HDEL", Jiggler.config.processes_hash, *to_prune) unless to_prune.empty?
        end

        to_prune.size
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
