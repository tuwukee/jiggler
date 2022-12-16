# frozen_string_literal: true

module Jiggler
  module Stats
    class Monitor
      include Support::Component
      MONITOR_FLAG = "jiggler:flag:monitor"

      attr_reader :collection, :data_key, :exp

      def initialize(config, collection)
        @config = config
        @collection = collection
        @done = false
        @condition = Async::Condition.new
        @data_key = "#{config.stats_prefix}#{collection.uuid}"
        @exp = config[:stats_interval] * 2
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
        @condition.signal
        @done = true
        cleanup
      end

      def load_data_into_redis
        process_data = JSON.generate({
          uuid: collection.uuid,
          heartbeat: Time.now.to_f,
          rss: process_rss,
          current_jobs: collection.data[:current_jobs],
        })
        logger.debug("Loading stats into redis") { process_data }

        redis do |conn| 
          conn.set(MONITOR_FLAG, "1", seconds: exp)
          conn.set(data_key, process_data, seconds: exp)
        end

        config.cleaner.unforsed_prune_outdated_processes_data(
          config.processes_hash, config.stats_prefix
        )
        logger.debug("Pruned outdated processes data...")
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
        redis { |conn| conn.del(data_key) }
      end

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
      end
    end
  end
end