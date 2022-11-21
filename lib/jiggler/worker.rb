# frozen_string_literal: true

module Jiggler
  class Worker
    include Component

    TIMEOUT = 5

    Job = Struct.new(:queue, :args, keyword_init: true)

    attr_reader :current_job

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
        rescue => ex
          @callback.call(self, ex)
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
      config.logger.info('fetched some')
      if queue
        if @done
          requeue(queue, args)
          nil
        else
          Job.new(queue:, args:)
        end
      end
    rescue Async::Stop
    rescue => ex
      binding.break
      handle_fetch_error(ex)
    end
    
    def execute_job
      parsed_args = JSON.parse(current_job.args)
      acc = false
      begin
        execute(parsed_args, current_job.queue)
        acc = true
      rescue Async::Stop
      rescue Jiggler::Retry::Handled => h
        # this is the common case: job raised error and Jiggler::Retry::Handled
        # signals that we created a retry successfully. We can acknowlege the job.
        ack = true
        e = h.cause || h
        handle_exception(e, { context: "Job raised exception", job: job_hash })
        raise e
      rescue Exception => ex
        # Unexpected error! This is very bad and indicates an exception that got past
        # the retry subsystem (e.g. network partition). We won't acknowledge the job
        # so it can be rescued when using Sidekiq Pro.
        handle_exception(
          ex,
          {
            context: "Internal exception!",
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
      klass = Object.const_get(parsed_job["klass"])
      instance = klass.new
      args = parsed_job["args"]
      with_retry(instance, parsed_job, queue) do
        instance.perform(*args)
      end
    end

    def with_retry(instance, args, queue)
      Retrier.new(config).wrapped(instance, args, queue) do
        yield
      end
    end

    def requeue(queue, args)
      redis do |conn|
        conn.rpush(queue, args)
      end
    end

    def handle_fetch_error(ex)
      raise ex
      # pass
    end

    def send_to_dead
      # todo
    end

    def cleanup
      # log some stuff probably
    end

    def queues
      @queues ||= @config.queues
    end

    def constantize(str)
      return Object.const_get(str) unless str.include?("::")

      names = str.split("::")
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        # the false flag limits search for name to under the constant namespace
        #   which mimics Rails' behaviour
        constant.const_get(name, false)
      end
    end
  end
end
