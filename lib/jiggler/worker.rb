# frozen_string_literal: true

module Jiggler
  class Worker
    include Support::Component
    TIMEOUT = 2 # timeout for brpop

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

          # pass control to other fibers
          sleep(0)
          # sleep(0) appears to work slower than
          # Async::Task.current.yield
          # but it's more reliable
        rescue Async::Stop
          break @callback.call(self)
        rescue => err
          collection.incr_failures
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
      queue, args = config.with_sync_redis { |conn| conn.blocking_call(false, 'BRPOP', *queues, TIMEOUT) }
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
      # error_message='undefined method `zero?' for nil:NilClass' context='Fetch error' tid=1tpj
      # sometimes happens in async-pool-0.3.12/lib/async/pool/controller.rb:213:in `reuse'
      handle_fetch_error(err)
    end
    
    def execute_job
      parsed_args = JSON.parse(current_job.args)
      begin
        execute(parsed_args, current_job.queue)
        collection.incr_processed
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
      collection.incr_failures
      logger.error('Worker') { "Failed to parse job: #{current_job.args}" }
    end

    def execute(parsed_job, queue)
      klass = collection.fetch_job_class(parsed_job['name'])
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

    def queues
      @queues ||= config.prefixed_queues
    end
  end
end
