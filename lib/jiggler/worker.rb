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
      reason = nil
      @runner = safe_async('Worker') do
        @tid = tid
        loop do
          break @callback.call(self) if @done
          process_job
        rescue Async::Stop
          break @callback.call(self)
        rescue => err
          increase_failures_counter
          break @callback.call(self, err)     
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
      # retries for the case of recoverable redis connection errors
      retries ||= 0
      queue, args = config.with_sync_redis { |conn| conn.blocking_call(false, 'BRPOP', *queues, TIMEOUT) } if queue.nil?
      if queue
        if @done
          requeue(queue, args)
          nil
        else
          CurrentJob.new(queue: queue, args: args)
        end
      end
    rescue Async::Stop => err
      raise err
    rescue => err
      retry unless (retries += 1) > 2
      handle_fetch_error(err)
    end
    
    def execute_job
      parsed_args = JSON.parse(current_job.args)
      begin
        execute(parsed_args, current_job.queue)
        increase_processed_counter
      rescue Async::Stop => err
        raise err
      rescue UnknownJobError => err
        handle_exception(
          err,
          {
            error_class: err.class.name,
            job: parsed_args,
            tid: @tid
          },
          raise_ex: true
        )
      rescue Exception => ex
        handle_exception(
          ex,
          {
            context: '\'Internal exception\'',
            tid: @tid,
            jid: parsed_args['jid']
          },
          raise_ex: true
        )
      end
    rescue JSON::ParserError => err
      increase_failures_counter
      logger.error('Worker') { "Failed to parse job: #{current_job.args}" }
    end

    def execute(parsed_job, queue)
      klass = constantize(parsed_job['name'])
      instance = klass.new

      add_current_job_to_collection(parsed_job, klass.queue)
      retrier.wrapped(instance, parsed_job, queue) do
        instance.perform(*parsed_job['args'])
      end
    ensure
      remove_current_job_from_collection
    end

    def retrier
      @retrier ||= Jiggler::Retrier.new(config, collection)
    end

    def requeue(queue, args)
      config.with_async_redis do |conn|
        conn.call('RPUSH', queue, args)
      end
    end

    def handle_fetch_error(ex)
      handle_exception(
        ex,
        {
          context: '\'Fetch error\'',
          tid: @tid
        },
        raise_ex: true
      )
    end

    def add_current_job_to_collection(parsed_job, queue)
      collection.data[:current_jobs][@tid] = {
        job_args: parsed_job,
        queue: queue,
        started_at: Time.now.to_f
      }
    end

    def remove_current_job_from_collection
      collection.data[:current_jobs].delete(@tid)
    end

    def increase_processed_counter
      collection.data[:processed] += 1
    end

    def increase_failures_counter
      collection.data[:failures] += 1
    end

    def queues
      @queues ||= config.prefixed_queues
    end

    def constantize(str)
      return Object.const_get(str) unless str.include?('::')

      names = str.split('::')
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        constant.const_get(name, false)
      end
    rescue => err
      raise UnknownJobError, 'Cannot initialize job'
    end
  end
end
