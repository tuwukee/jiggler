# frozen_string_literal: true

module Jiggler
  module Stats
    class Monitor
      include Support::Component
      PROCESSED_COUNTER = 'jiggler:stats:processed_counter'
      FAILURES_COUNTER = 'jiggler:stats:failures_counter'

      attr_reader :collection, :data_key, :exp

      def initialize(config, collection)
        @config = config
        @collection = collection
        @done = false
        @condition = Async::Condition.new
        @data_key = "#{config.stats_prefix}#{collection.uuid}"
        # expire the key after 6 intervals
        # this is to avoid the case where the monitor is blocked
        # by long running workers and the key is not updated
        @exp = config[:stats_interval] * 6
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
        # logger.debug('Monitor') { process_data }

        processed_jobs = collection.data[:processed]
        failed_jobs = collection.data[:failures]
        collection.data[:processed] -= processed_jobs
        collection.data[:failures] -= failed_jobs

        config.with_sync_redis do |conn|
          conn.pipelined do |pipeline|
            pipeline.call('SET', data_key, process_data, ex: exp)
            pipeline.call('INCRBY', PROCESSED_COUNTER, processed_jobs)
            pipeline.call('INCRBY', FAILURES_COUNTER, failed_jobs)
          end
        end
        # logger.warn result

        Async { config.cleaner.unforced_prune_outdated_processes_data }
      rescue => ex
        handle_exception(
          ex, { context: '\'Error while loading stats into redis\'', tid: @tid }
        )
      end

      def process_rss
        case RUBY_PLATFORM
        when /linux/
          IO.readlines(@rss_path).each do |line|
            next unless line.start_with?('VmRSS:')
            break line.split[1].to_i
          end
        when /darwin|bsd/
          `ps -o pid,rss -p #{Process.pid}`.lines.last.split.last.to_i
        else
          nil
        end
      end

      def cleanup
        config.with_async_redis { |conn| conn.call('DEL', data_key) }
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
