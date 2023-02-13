# frozen_string_literal: true

require 'set'

# This class manages the workers lifecycle
module Jiggler
  class Manager
    include Support::Helper

    def initialize(config, collection)
      @workers = Set.new

      @done = false
      @config = config
      @timeout = @config[:timeout]
      @collection = collection
      init_acknowledger_and_fetcher

      @config[:concurrency].times do
        @workers << init_worker
      end
    end

    def start
      @acknowledger.start
      @fetcher.start
      @workers.each(&:run)
    end

    def suspend
      return if @done

      @done = true
      @fetcher.suspend
    end

    def terminate
      suspend
      schedule_shutdown
      wait_for_workers
      wait_for_acknowledger
    end

    private

    def init_acknowledger_and_fetcher
      if @config.at_least_once?
        @fetcher = AtLeastOnce::Fetcher.new(@config, @collection)
        @acknowledger = AtLeastOnce::Acknowledger.new(@config)
      else
        @fetcher = AtMostOnce::Fetcher.new(@config, @collection)
        @acknowledger = AtMostOnce::Acknowledger.new(@config)
      end
    end

    def wait_for_acknowledger
      logger.info('Waiting for the finished jobs to acknowledge...')
      @acknowledger.terminate
      @acknowledger.wait
    end

    def wait_for_workers
      logger.info('Waiting for workers to finish...')
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
        @config, @collection, @acknowledger, @fetcher, &method(:process_worker_result)
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
      logger.warn('Hard shutdown, terminating workers...')
      @workers.each(&:terminate)
    end
  end
end 
