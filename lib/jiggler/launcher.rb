# frozen_string_literal: true

module Jiggler
  class Launcher
    include Support::Component

    attr_reader :config

    def initialize(config)
      @done = false
      @config = config
    end

    def start
      poller.start if config[:poller_enabled]
      monitor.start
      manager.start
    end

    def suspend
      return if @done

      @done = true
      manager.suspend

      poller.terminate if config[:poller_enabled]
      monitor.terminate
    end

    def stop
      suspend
      manager.terminate
    end

    private

    def uuid
      @uuid ||= begin
        data_str = [
          SecureRandom.hex(6),
          ENV['DYNO'] || Socket.gethostname,
          config[:concurrency],
          config[:timeout],
          config[:queues].join(','),
          config[:poller_enabled] ? '1' : '0',
          Time.now.to_i,
          Process.pid
        ].join(':')
        "#{config.server_prefix}#{data_str}"
      end
    end

    def collection
      @collection ||= Stats::Collection.new(uuid)
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
