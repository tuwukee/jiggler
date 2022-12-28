# frozen_string_literal: true

require 'async'
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

    def poller_badge(poller_enabled)
      poller_enabled ? '<span class=\'badge badge-success\'>Polling</span>' : '<span class=\'badge\'>Polling Disabled</span>'
    end

    def styles
      @styles ||= File.read(STYLESHEET)
    end
  end
end
