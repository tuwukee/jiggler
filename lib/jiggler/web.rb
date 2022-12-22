# frozen_string_literal: true

require 'async'
require 'erb'

module Jiggler
  class Web
    WEB_PATH = File.expand_path("#{File.dirname(__FILE__)}/web")
    LAYOUT = "#{WEB_PATH}/views/application.erb"
    STYLESHEET = "#{WEB_PATH}/assets/stylesheets/application.css"

    def call(env)
      @summary = Jiggler::Summary.all
      compiled_template = ERB.new(File.read(LAYOUT)).result(binding)
      [200, {}, [compiled_template]]
    end

    def last_5_dead_jobs
      Jiggler.redis(async: false) do |conn|
        conn.call('ZRANGE', Jiggler.config.dead_set, -5, -1)
      end.map { |job| JSON.parse(job) }
    end

    def last_5_retry_jobs
      Jiggler.redis(async: false) do |conn|
        conn.call('ZRANGE', Jiggler.config.retries_set, -5, -1)
      end.map { |job| JSON.parse(job) }
    end

    def last_5_scheduled_jobs
      Jiggler.redis(async: false) do |conn|
        conn.call('ZRANGE', Jiggler.config.scheduled_set, -5, -1, 'WITHSCORES')
      end.map do |(job, score)|
        JSON.parse(job).merge('scheduled_at' => score)
      end
    end

    def format_datetime(timestamp)
      return if timestamp.nil?
      Time.at(timestamp.to_f).to_datetime
    end

    def format_memory(kb)
      return '?' if kb.nil?
      "#{(kb/1024.0).round(2)} MB"
    end

    def monitored_badge(stats_enabled)
      stats_enabled ? '<span class=\'badge badge-success\'>Monitored</span>' : '<span class=\'badge\'>Unmonitored</span>'
    end

    def styles
      @styles ||= File.read(STYLESHEET)
    end
  end
end
