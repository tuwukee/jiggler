# frozen_string_literal: true

require_relative "./errors"

module Jiggler
  class Worker
    include Component
    TIMEOUT = 5 # timeout for brpop

    CurrentJob = Struct.new(:queue, :args, keyword_init: true)

    attr_reader :current_job, :config, :done

    def initialize(config, &callback)
      @done = false
      @current_job = nil
      @callback = callback
      @config = config
    end

    def run
      @runner = safe_async("worker") do
        loop do
          break @callback.call(self) if @done
          process_job
        rescue Async::Stop
          cleanup
          @callback.call(self)
          break
        rescue => ex
          @callback.call(self, ex)
          break
        end
      end
    end

    def terminate
      @done = true
      @runner&.stop
    end

    def quite
      @done = true
    end

    def wait
      @runner.wait
    end

    private

    def process_job
      @current_job = fetch_one
      return if current_job.nil? # timed out brpop or done
      execute_job
      @current_job = nil
    end

    def fetch_one
      queue, args = redis(async: false) { |conn| conn.brpop(*queues, timeout: TIMEOUT) }
      if queue
        if @done
          requeue(queue, args)
          nil
        else
          CurrentJob.new(queue: queue, args: args)
        end
      end
    rescue Async::Stop => e
      logger.debug("Async::Stop in fetch_one")
      raise e
    rescue => ex
      handle_fetch_error(ex)
    end
    
    # TODO: review this
    def execute_job
      parsed_args = JSON.parse(current_job.args)
      acc = false
      begin
        execute(parsed_args, current_job.queue)
        acc = true
      rescue Async::Stop => e
        logger.debug("Async::Stop in execute_job")
        raise e
      rescue Jiggler::RetryHandled => h
        ack = true
        e = h.cause || h
        handle_exception(e, { context: "Job raised exception", job: job_hash })
        raise e
      rescue Exception => ex
        handle_exception(
          ex,
          {
            context: "Internal exception",
            job: parsed_args,
            jobstr: current_job.args
          }
        )
        raise ex
      ensure
        acknowledge if acc
      end
    rescue JSON::ParserError
      send_to_dead
    end

    def execute(parsed_job, queue)
      klass = Object.const_get(parsed_job["name"])
      instance = klass.new
      args = parsed_job["args"]

      logger.info("Executing #{klass} on #{instance.queue} tid=#{tid} jid=#{instance.jid}")
      with_retry(instance, parsed_job, queue) do
        instance.perform(*args)
      end
      logger.info("Done tid=#{tid} jid=#{instance.jid}")
    end

    def with_retry(instance, args, queue)
      retrier.wrapped(instance, args, queue) do
        yield
      end
    end

    def retrier
      @retrier ||= Jiggler::Retrier.new(config)
    end

    def requeue(queue, args)
      redis do |conn|
        conn.rpush(queue, args)
      end
    end

    def handle_fetch_error(ex)
      config.logger.error("Fetch error: #{ex}")
      raise ex
      # pass
    end

    def send_to_dead
      config.logger.warn("Send to dead: #{current_job.inspect}")
      # todo
    end

    def cleanup
      config.logger.debug("Cleanup")
      # log some stuff probably
    end

    def queues
      @queues ||= config.queues_hash.values
    end

    def constantize(str)
      return Object.const_get(str) unless str.include?("::")

      names = str.split("::")
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        constant.const_get(name, false)
      end
    end
  end
end
