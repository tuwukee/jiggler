# frozen_string_literal: true

require "async"
require "erb"

module Jiggler
  class Web
    WEB_PATH = File.expand_path("#{File.dirname(__FILE__)}/web")
    LAYOUT = "#{WEB_PATH}/views/application.erb"
    STYLESHEET = "#{WEB_PATH}/assets/stylesheets/application.css"

    def call(env)
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

    def indentity(data)
      "#{data[1]["hostname"] - data[1]["pid"]}"
    end

    def processed_count
      0 # Jiggler.redis(async: false) { |conn| conn.call("get", Jiggler.processed_counter) }
    end

    def failed_count
      0 # Jiggler.redis(async: false) { |conn| conn.call("get", Jiggler.failed_counter) }
    end

    def styles
      @styles ||= File.read(STYLESHEET)
    end
  end
end
