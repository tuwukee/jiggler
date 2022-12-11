# frozen_string_literal: true

require_relative "./manager"
require_relative "./component"
require_relative "./scheduled"

module Jiggler
  class Launcher
    include Component

    attr_reader :config

    def initialize(config)
      @done = false
      @manager = Manager.new(config)
      @poller = Scheduled::Poller.new(config)
      @config = config
      @uuid = "jiggler-#{SecureRandom.hex(6)}"
    end

    def start
      set_process_data
      @manager.start
      @poller.start
    end

    def quite
      return if @done

      @done = true
      @manager.quite
      @poller.terminate
    end

    def stop
      quite
      @manager.terminate
    end

    def hostname
      ENV["DYNO"] || Socket.gethostname
    end

    def process_data
      {
        pid: Process.pid,
        hostname: hostname,
        concurrency: config[:concurrency],
        queues: config[:queues].join(", "),
        started_at: Time.now.to_s,
      }.to_json
    end

    def cleanup
      redis { |conn| conn.call("hdel", config.processes_hash, @uuid) }
    end

    def set_process_data
      redis { |conn| conn.call("hset", config.processes_hash, @uuid, process_data) }
    end
  end
end
