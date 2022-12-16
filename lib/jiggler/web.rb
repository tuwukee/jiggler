# frozen_string_literal: true

require "async"
require "erb"

module Jiggler
  class Web
    WEB_PATH = File.expand_path("#{File.dirname(__FILE__)}/web")
    LAYOUT = "#{WEB_PATH}/views/application.erb"
    STYLESHEET = "#{WEB_PATH}/assets/stylesheets/application.css"

    def call(env)
      @retry_jobs_count = retry_jobs_count
      @dead_jobs_count = dead_jobs_count
      @monitor_enabled = Jiggler.redis(async: false) do |conn|
        conn.call("get", Jiggler::Stats::Monitor::MONITOR_FLAG)
      end
      fetch_and_format_data

      compiled_template = ERB.new(File.read(LAYOUT)).result(binding)
      [200, {}, [compiled_template]]
    end

    # current_jobs entry example:
    # {"2gx":{"jid":"8639997c1d5d5a12","job_args":{"name":"MyJob","args":{},"retries":0},"started_at":1671059371.245427}
    def fetch_and_format_data
      @processes_data = {}

      processes.each_slice(2) do |uuid, process_data|
        parsed_process_data = JSON.parse(process_data)
        if parsed_process_data["stats_enabled"]
          stats_data = Jiggler.redis(async: false) do |conn| 
            conn.get("#{Jiggler.config.stats_prefix}#{uuid}")
          end
          parsed_process_data.merge!(JSON.parse(stats_data)) if stats_data
        end
        parsed_process_data["current_jobs"] ||= []
        @processes_data[uuid] = parsed_process_data
      end
    end

    def processes
      @processes ||= Jiggler.redis(async: false) do |conn| 
        conn.call("hgetall", Jiggler.config.processes_hash) 
      end
    end

    def queues
      lists = Jiggler.redis(async: false) { |conn| conn.call("keys", "jiggler:list:*") }
      lists.map do |list|
        name = list.split(":").last
        [name, Jiggler.redis(async: false) { |conn| conn.call("llen", list) }]
      end
    end

    def retry_jobs_count
      Jiggler.redis(async: false) do |conn| 
        conn.call("zcard", Jiggler.config.retries_set)
      end
    end

    def dead_jobs_count
      Jiggler.redis(async: false) do |conn| 
        conn.call("zcard", Jiggler.config.dead_set)
      end
    end

    def last_5_dead_jobs
      Jiggler.redis(async: false) do |conn|
        conn.call("zrange", Jiggler.config.dead_set, -5, -1)
      end.map { |job| JSON.parse(job) }
    end

    def last_5_retry_jobs
      Jiggler.redis(async: false) do |conn|
        conn.call("zrange", Jiggler.config.retries_set, -5, -1)
      end.map { |job| JSON.parse(job) }
    end

    def format_datetime(timestamp)
      return if timestamp.nil?
      Time.at(timestamp.to_f).to_datetime
    end

    def format_memory(kb)
      return "?" if kb.nil?
      "#{(kb/1024.0).round(2)} MB"
    end

    def monitored_badge(stats_enabled)
      stats_enabled ? "<span class='badge badge-success'>Monitored</span>" : "<span class='badge'>Unmonitored</span>"
    end

    def styles
      @styles ||= File.read(STYLESHEET)
    end
  end
end
