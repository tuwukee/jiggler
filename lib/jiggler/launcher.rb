# frozen_string_literal: true

module Jiggler
  class Launcher
    include Support::Component

    attr_reader :config

    def initialize(config)
      @done = false
      @config = config
      @uuid = "jiggler-#{SecureRandom.hex(6)}"
    end

    def start
      set_process_data
      manager.start
      poller.start if config[:poller_enabled]
      monitor.start
    end

    def quite
      return if @done

      @done = true
      manager.quite

      poller.terminate if config[:poller_enabled]
      monitor.terminate
      cleanup
    end

    def stop
      quite
      manager.terminate
    end

    def hostname
      ENV['DYNO'] || Socket.gethostname
    end

    def process_data
      {
        pid: Process.pid,
        hostname: hostname,
        concurrency: config[:concurrency],
        timeout: config[:timeout],
        queues: config[:queues].join(', '),
        started_at: Time.now.to_f,
        poller_enabled: config[:poller_enabled]
      }.to_json
    end

    def cleanup
      config.with_async_redis { |conn| conn.call('HDEL', config.processes_hash, @uuid) }
    end

    # using a sync call to throw an error an early exit if redis is down
    def set_process_data
      config.with_sync_redis { |conn| conn.call('HSET', config.processes_hash, @uuid, process_data) }
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
