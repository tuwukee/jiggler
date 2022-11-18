# frozen_string_literal: true

require "async"
require "securerandom"
require_relative "./component"

module Jiggler
  class Manager
    include Component

    def initialize(config)
      @workers = Set.new
      @done = false
      @config = config
      @notification = Async::IO::Notification.new
      @shutdown_timeout = @config[:shutdown_timeout]
      (@config[:count] || Jiggler.config[:concurrency]).times do
        @workers << init_worker
      end
      @uuid = SecureRandom.uuid
    end

    def start
      @workers.each(&:run)
    end

    def quite
      return if @done

      @done = true
      @workers.each(&:quite)
    end

    def terminate
      quite
      schedule_shutdown
      wait_for_workers
    end

    private

    def wait_for_workers
      @workers.each(&:wait)
      @shutdown_task.stop
    end

    def schedule_shutdown
      @shutdown_task = Async do
        sleep(@shutdown_timeout)

        next if @workers.empty?

        hard_shutdown
      end
    end

    def init_worker
      Worker.new(
        **{
          callback: method(:process_worker_result),
          config: @worker_config
        }
      )
    end

    def process_worker_result(worker, reason = nil)
      @workers.delete(worker)
      unless @done
        new_worker = init_worker
        @workers << new_worker
        new_worker.start
      end
    end

    def hard_shutdown
      @workers.each(&:terminate)
    end
  end
end 
