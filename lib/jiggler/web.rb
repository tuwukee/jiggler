# frozen_string_literal: true

require 'erb'

module Jiggler
  class Web
    WEB_PATH = File.expand_path("#{File.dirname(__FILE__)}/web")
    LAYOUT = "#{WEB_PATH}/views/application.erb"
    STYLESHEET = "#{WEB_PATH}/assets/stylesheets/application.css"

    def call(env)
      @summary_instance = Jiggler::Summary.new(Jiggler.config)
      @summary = @summary_instance.all
      compiled_template = ERB.new(File.read(LAYOUT)).result(binding)
      [200, {}, [compiled_template]]
    end

    def last_5_dead_jobs
      @summary_instance.last_dead_jobs(5)
    end

    def last_5_retry_jobs
      @summary_instance.last_retry_jobs(5)
    end

    def last_5_scheduled_jobs
      @summary_instance.last_scheduled_jobs(5)
    end

    def format_datetime(timestamp)
      return if timestamp.nil?
      Time.at(timestamp.to_f).to_datetime
    end

    def format_memory(kb)
      return '?' if kb.nil?
      "#{(kb/1024.0).round(2)} MB"
    end

    def time_ago_in_words(timestamp)
      return if timestamp.nil?
      seconds = Time.now.to_i - timestamp.to_i
      case seconds
      when 0..59
        "#{seconds} seconds ago"
      when 60..3599
        "#{(seconds/60).round} minutes ago"
      when 3600..86399
        "#{(seconds/3600).round} hours ago"
      when 86400..604799
        "#{(seconds/86400).round} days ago"
      else
        "#{(seconds/604800).round} weeks ago"
      end
    end

    def heartbeat_class(timestamp)
      return 'outdated' if outdated_heartbeat?(timestamp)
    end

    def outdated_heartbeat?(timestamp)
      return true if timestamp.nil?
      seconds = Time.now.to_i - timestamp.to_i
      seconds > Jiggler.config[:stats_interval] * 2
    end

    def poller_badge(poller_enabled)
      poller_enabled ? '<span class=\'badge badge-success\'>Polling</span>' : '<span class=\'badge\'>Polling Disabled</span>'
    end

    def styles
      @styles ||= File.read(STYLESHEET)
    end
  end
end
