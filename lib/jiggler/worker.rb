# frozen_string_literal: true

module Jiggler
  class Worker
    include Support::Component
    TIMEOUT = 5 # timeout for brpop

    CurrentJob = Struct.new(:queue, :args, keyword_init: true)

    attr_reader :current_job, :config, :done, :collection

    def initialize(config, collection, &callback)
      @done = false
      @current_job = nil
      @callback = callback
      @config = config
      @collection = collection
    end

    def run
      @runner = safe_async("worker") do
        loop do
          break @callback.call(self) if @done
          process_job
        rescue Async::Stop
          # cleanup (?)
          @callback.call(self)
          break
        rescue => ex
          increase_failures_counter
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
      @runner&.wait
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
      raise e
    rescue => ex
      handle_fetch_error(ex)
    end
    
    def execute_job
      parsed_args = JSON.parse(current_job.args)
      begin
        execute(parsed_args, current_job.queue)
        increase_processed_counter
      rescue Async::Stop => err
        raise err
      rescue Jiggler::RetryHandled => handled
        err = handled.cause || handled
        handle_exception(
          err, 
          { 
            context: "'Job raised exception'",
            tid: tid
          }.merge(parsed_args),
          raise_ex: true
        )
      rescue Exception => ex
        handle_exception(
          ex,
          {
            context: "'Internal exception'",
            tid: tid
          }.merge(parsed_args),
          raise_ex: true
        )
      end
    rescue JSON::ParserError
      increase_failures_counter
      send_to_dead
    end

    def execute(parsed_job, queue)
      klass = Object.const_get(parsed_job["name"])
      instance = klass.new
      args = parsed_job["args"]

      logger.info("Starting #{klass} queue=#{klass.queue} tid=#{tid} jid=#{instance._jid}")
      add_current_job_to_collection(instance._jid, parsed_job)
      with_retry(instance, parsed_job, queue) do
        instance.perform(*args)
      end
      logger.info("Finished #{klass} queue=#{klass.queue} tid=#{tid} jid=#{instance._jid}")
    ensure
      logger.debug("Removing job #{instance._jid}...")
      remove_current_job_from_collection
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
      handle_exception(
        ex,
        {
          context: "Fetch error",
          tid: tid
        },
        raise_ex: true
      )
    end

    def add_current_job_to_collection(jid, parsed_job)
      return unless config[:stats_enabled]
      collection.data[:current_jobs][tid] = {
        jid: jid,
        job_args: parsed_job,
        started_at: Time.now.to_f
      }
    end

    def remove_current_job_from_collection
      return unless config[:stats_enabled]
      collection.data[:current_jobs].delete(tid)
    end

    def increase_processed_counter
      return unless config[:stats_enabled]
      collection.data[:processed] += 1
    end

    def increase_failures_counter
      return unless config[:stats_enabled]
      collection.data[:failures] += 1
    end

    def send_to_dead
      config.logger.warn("Send to dead: #{current_job.inspect}")
      # todo
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
