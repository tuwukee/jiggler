# frozen_string_literal: true

require "async"
require "securerandom"

module Jiggler
  class Manager
    include Support::Component

    def initialize(config, collection)
      @workers = Set.new
      @done = false
      @config = config
      @timeout = @config[:timeout]
      @collection = collection
      @config[:concurrency].times do
        @workers << init_worker
      end
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
        sleep(@timeout)

        next if @workers.empty?

        hard_shutdown
      end
    end

    def init_worker
      Jiggler::Worker.new(
        config, @collection, &method(:process_worker_result)
      )
    end

    def process_worker_result(worker, reason = nil)
      @workers.delete(worker)
      unless @done
        new_worker = init_worker
        @workers << new_worker
        new_worker.run
      end
    end

    def hard_shutdown
      @workers.each(&:terminate)
    end
  end
end 
