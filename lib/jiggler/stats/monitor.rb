# frozen_string_literal: true

module Jiggler
  module Stats
    class Monitor
      include Support::Component
      include Support::Cleaner

      MONITOR_FLAG = "jiggler:flag:monitor"

      attr_reader :collection

      def initialize(config, collection)
        @config = config
        @collection = collection
        @done = false
        @condition = Async::Condition.new
      end

      def start
        @job = safe_async("Monitor") do
          wait # initial wait
          until @done
            load_data_into_redis
            wait unless @done
          end
        end
      end

      def terminate
        cleanup
        @done = true
      end

      def load_data_into_redis
        process_data = JSON.generate({
          heartbeat: Time.now.to_f,
          rss: process_rss,
          current_jobs: collection.data[:current_jobs],
        })
        logger.debug("Loading stats into redis: #{process_data}")
        redis { |conn| conn.set(MONITOR_FLAG, "1", update: false, seconds: config[:stats_interval] * 3) }
        redis { |conn| conn.call("hset", config.stats_hash, collection.uuid, process_data) }

        prune_outdated_processes_data(config.stats_hash)
      end

      def process_rss
        IO.readlines("/proc/#{Process.pid}/status").each do |line|
          next unless line.start_with?("VmRSS:")
          break line.split[1].to_i
        end
      rescue => ex
        handle_exception(
          ex, { context: "'Error while getting process RSS'", tid: tid }
        )
      end

      def cleanup
        logger.debug("Cleaning up stats...")
        redis { |conn| conn.del(MONITOR_FLAG) }
        redis { |conn| conn.call("hdel", config.stats_hash, collection.uuid) }
      end

      # todo: can it be simpler?
      def wait
        Async(transient: true) do
          sleep(config[:stats_interval])
          @condition.signal
        end
        @condition.wait
      rescue => ex
        handle_exception(
          ex, { context: "'Error while waiting for stats'", tid: tid }
        )
        sleep(5)
      end
    end
  end
end
