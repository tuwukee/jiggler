# frozen_string_literal: true

module Jiggler
  module Stats
    class Monitor
      include Support::Helper

      attr_reader :collection, :data_key, :exp

      def initialize(config, collection)
        @config = config
        @collection = collection
        @done = false
        @condition = Async::Condition.new
        # the key expiration should be greater than the stats interval
        # to avoid cases where the monitor is blocked
        # by long running workers and the key is not updated in time
        @exp = config[:stats_interval] + 300 # interval + 5 minutes
        @rss_path = "/proc/#{Process.pid}/status"
      end

      def start
        @job = safe_async('Monitor') do
          @tid = tid
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
  
      def process_data
        Oj.dump({
          heartbeat: Time.now.to_f,
          rss: process_rss,
          current_jobs: collection.data[:current_jobs],
        }, mode: :compat)
      end

      def load_data_into_redis
        # logger.warn("Monitor runs")
        processed_jobs = collection.data[:processed]
        failed_jobs = collection.data[:failures]
        collection.data[:processed] -= processed_jobs
        collection.data[:failures] -= failed_jobs

        config.with_async_redis do |conn|
          conn.pipelined do |pipeline|
            pipeline.call('SET', collection.uuid, process_data, ex: exp)
            pipeline.call('INCRBY', config.processed_counter, processed_jobs)
            pipeline.call('INCRBY', config.failures_counter, failed_jobs)
          end
        end
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
        config.with_async_redis { |conn| conn.call('DEL', collection.uuid) }
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
