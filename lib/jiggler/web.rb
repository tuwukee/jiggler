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

      compiled_template = ERB.new(File.read(LAYOUT)).result(binding)
      [200, {}, [compiled_template]]
    end

    # TODO: refactor this pleaseee :(
    # {"2gx":{"jid":"8639997c1d5d5a12","job_args":{"name":"MyJob","args":{},"retries":0},"started_at":1671059371.245427}
    def processes_data
      Jiggler.redis(async: false) do |conn| 
        conn.call("hgetall", Jiggler.config.processes_hash) 
      end.each_slice(2).map do |uuid, process_data|
        parsed_process_data = JSON.parse(process_data)
        stats_data = Jiggler.redis(async: false) { |conn| conn.call("hget", Jiggler.config.stats_hash, uuid) }
        parsed_process_data.merge!(JSON.parse(stats_data)) if stats_data
        [uuid, parsed_process_data] 
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

    def styles
      @styles ||= File.read(STYLESHEET)
    end
  end
end
