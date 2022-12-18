# frozen_string_literal: true

module Jiggler
  class Summary
    class << self
      def all
        summary = {}
        collected_data = Jiggler.redis(async: false) do |conn|
          conn.pipeline do |pipeline|
            data = pipeline.collect do
              pipeline.call("zcard", Jiggler.config.retries_set).to_i
              pipeline.call("zcard", Jiggler.config.dead_set).to_i
              pipeline.call("get", Jiggler::Stats::Monitor::MONITOR_FLAG)
              pipeline.call("get", Jiggler::Stats::Monitor::FAILURES_STATS)
              pipeline.call("get", Jiggler::Stats::Monitor::PROCESSED_STATS)
            end
            [*data, fetch_and_format_processes(conn), fetch_and_format_queues(conn)]
          end
        end
        %w[
          retry_jobs_count dead_jobs_count monitor_enabled
          failures_count processed_count processes queues
        ].each_with_index do |key, index|
          summary[key] = collected_data[index]
        end
        summary
      end

      private

      def fetch_and_format_processes(conn)
        processes = conn.call("hgetall", Jiggler.config.processes_hash)
        processes_data = {}

        collected_data = conn.pipeline do |pipeline|
          pipeline.collect do
            processes.each_slice(2) do |uuid, process_data|
              processes_data[uuid] = JSON.parse(process_data)
              if processes_data[uuid]["stats_enabled"]
                pipeline.get("#{Jiggler.config.stats_prefix}#{uuid}")
              end
            end
          end
        end
        
        processes.each_slice(2) do |uuid, _|
          if processes_data[uuid]["stats_enabled"]
            stats_data = collected_data.shift
            processes_data[uuid].merge!(JSON.parse(stats_data)) if stats_data
          end
          processes_data[uuid]["current_jobs"] ||= []
        end
        processes_data
      end

      def fetch_and_format_queues(conn)
        lists = conn.call("keys", "#{Jiggler.config.queue_prefix}*")
        lists_data = {}

        collected_data = conn.pipeline do |pipeline|
          pipeline.collect do
            lists.each do |list|
              pipeline.call('llen', list)
            end
          end
        end
        lists.each_with_index do |list, index|
          lists_data[list.split(":").last] = collected_data[index]
        end
        lists_data
      end
    end
  end
end
