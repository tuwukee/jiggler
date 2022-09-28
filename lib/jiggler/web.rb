# frozen_string_literal: true

require "async"

module Jiggler
  class Web
    def call(env)
      [200, {}, ["Hello World! #{processes_list}"]]
    end

    def processes_list
      Sync { Jiggler.redis_client.call("smembers", Jiggler.processes_list) } 
    end
  end
end
