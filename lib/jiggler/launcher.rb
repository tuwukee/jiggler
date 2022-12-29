# frozen_string_literal: true

module Jiggler
  class Launcher
    include Support::Component

    attr_reader :config

    def initialize(config)
      @done = false
      @config = config
      @uuid = "#{config.server_prefix}#{Time.now.to_i}:#{SecureRandom.hex(4)}"
    end

    def start
      poller.start if config[:poller_enabled]
      monitor.start
      manager.start
    end

    def quite
      return if @done

      @done = true
      manager.quite

      poller.terminate if config[:poller_enabled]
      monitor.terminate
    end

    def stop
      quite
      manager.terminate
    end

    private

    def collection
      @collection ||= Stats::Collection.new(@uuid)
    end

    def manager
      @manager ||= Manager.new(config, collection)
    end

    def poller
      @poller ||= Scheduled::Poller.new(config)
    end

    def monitor
      @monitor ||= Stats::Monitor.new(config, collection)
    end
  end
end
