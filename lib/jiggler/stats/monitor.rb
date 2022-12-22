# frozen_string_literal: true

module Jiggler
  module Stats
    class Monitor
      include Support::Component
      MONITOR_FLAG = 'jiggler:flag:monitor'
      PROCESSED_COUNTER = 'jiggler:stats:processed_counter'
      FAILURES_COUNTER = 'jiggler:stats:failures_counter'

      attr_reader :collection, :data_key, :exp

      def initialize(config, collection)
        @config = config
        @collection = collection
        @done = false
        @condition = Async::Condition.new
        @data_key = "#{config.stats_prefix}#{collection.uuid}"
        @exp = config[:stats_interval] * 2
        @rss_path = "/proc/#{Process.pid}/status"
      end

      def start
        @job = safe_async('Monitor') do
          @tid = tid
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
        logger.debug('Monitor') { process_data }
        processed_jobs = collection.data[:processed]
        failed_jobs = collection.data[:failures]
        collection.data[:processed] -= processed_jobs
        collection.data[:failures] -= failed_jobs

        config.with_sync_redis do |conn|
          conn.pipelined do |pipeline|
            pipeline.call('SET', MONITOR_FLAG, '1', ex: exp)
            pipeline.call('SET', data_key, process_data, ex: exp)
            pipeline.call('INCRBY', PROCESSED_COUNTER, processed_jobs)
            pipeline.call('INCRBY', FAILURES_COUNTER, failed_jobs)
          end
        end

        config.cleaner.unforsed_prune_outdated_processes_data
      rescue => ex
        Jiggler.logger.info(ex.inspect)
        Jiggler.logger.info(ex.backtrace.join("\n"))
        handle_exception(
          ex, { context: '\'Error while loading stats into redis\'', tid: @tid }
        )
      end

      def process_rss
        IO.readlines(@rss_path).each do |line|
          next unless line.start_with?('VmRSS:')
          break line.split[1].to_i
        end
      end

      def cleanup
        redis { |conn| conn.call('DEL', data_key) }
      rescue => ex
        handle_exception(
          ex, { context: '\'Error while cleaning up stats\'', tid: @tid }
        )
      end

      def wait
        Async(transient: true) do
          sleep(config[:stats_interval])
          @condition.signal
        end
        @condition.wait
      rescue => ex
        handle_exception(
          ex, { context: '\'Error while waiting for stats\'', tid: @tid }
        )
      end
    end
  end
end
