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

    def processes_set
      Sync { Jiggler.redis_client.call("smembers", Jiggler.processes_set) } 
    end

    def processed_count
      Sync { Jiggler.redis_client.call("get", Jiggler.processed_counter) }
    end

    def failed_count
      Sync { Jiggler.redis_client.call("get", Jiggler.failed_counter) }
    end

    def styles
      @styles ||= File.read(STYLESHEET)
    end
  end
end
