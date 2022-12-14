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
      compiled_template = ERB.new(File.read(LAYOUT)).result(binding)
      [200, {}, [compiled_template]]
    end

    def processes_data
      Jiggler.redis(async: false) do |conn| 
        conn.call("hgetall", Jiggler.config.processes_hash) 
      end.each_slice(2).map { |k, v| [k, JSON.parse(v)] }
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

    def styles
      @styles ||= File.read(STYLESHEET)
    end
  end
end
