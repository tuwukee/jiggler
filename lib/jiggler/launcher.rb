# frozen_string_literal: true

require_relative "./manager"
require_relative "./scheduled"
require_relative "./component"

module Jiggler
  class Launcher
    include Component

    def initialize(config)
      @done = false
      @uuid = SecureRandom.uuid
      @manager = Manager.new(config)
      @config = config
      # @scheduler = Scheduled::Poller.new(config)
    end

    def start
      set_process_uuid
      @manager.start
      # @scheduler.start
    end

    def quiet
      return if @done

      @done = true
      @manager.quite
      # @scheduler.terminate
    end

    def stop
      quiet
      @manager.terminate
    end

    def cleanup
      redis { |conn| conn.call("srem", config.processes_set, @uuid) }
    end

    def set_process_uuid
      redis { |conn| conn.call("sadd", config.processes_set, @uuid) }
    end
  end
end
