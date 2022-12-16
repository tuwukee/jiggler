# frozen_string_literal: true

module Jiggler
  class Summary
    class << self
      def all
        summary = {}
        Jiggler.redis(async: false) do |conn|
          summary["retry_jobs_count"] = conn.call("zcard", Jiggler.config.retries_set).to_i
          summary["dead_jobs_count"] = conn.call("zcard", Jiggler.config.dead_set).to_i
          summary["monitor_enabled"] = conn.call("get", Jiggler::Stats::Monitor::MONITOR_FLAG)
          
          summary["processes"] = fetch_and_format_processes(conn)
          summary["queues"] = fetch_and_format_queues(conn)
        end
        summary
      end

      private

      def fetch_and_format_processes(conn)
        processes = conn.call("hgetall", Jiggler.config.processes_hash)
        processes_data = {}

        processes.each_slice(2) do |uuid, process_data|
          parsed_process_data = JSON.parse(process_data)
          if parsed_process_data["stats_enabled"]
            stats_data = conn.get("#{Jiggler.config.stats_prefix}#{uuid}")
            parsed_process_data.merge!(JSON.parse(stats_data)) if stats_data
          end
          parsed_process_data["current_jobs"] ||= []
          processes_data[uuid] = parsed_process_data
        end
        processes_data
      end

      def fetch_and_format_queues(conn)
        lists = conn.call("keys", "#{Jiggler.config.queue_prefix}*")
        lists_data = {}
        lists.each do |list|
          lists_data[list.split(":").last] = conn.call("llen", list)
        end
        lists_data
      end
    end
  end
end
