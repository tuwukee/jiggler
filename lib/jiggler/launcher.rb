# frozen_string_literal: true

require "async"
require "securerandom"
require_relative "./executor_pool"
require_relative "./jobs_temp"

module Jiggler
  class Launcher
    attr_reader :queues, :processing_queue

    def initialize(uuid: SecureRandom.uuid)
      @lists = Jiggler.config[:lists] 
      @executor_pool = Jiggler::ExecutorPool.new(concurrency: Jiggler.config[:concurrency])
      @uuid = uuid
    end

    def run
      set_process_uuid
      set_counters

      Async do
        loop do
          # TODO: use processing queue?
          # job_args = Jiggler.redis_client.brpoplpush(queue, Jiggler.processing_queue, 0)
          # job_args = {}
          # Jiggler.redis_client.transaction do |context|
            # queue, job_args = Jiggler.redis_client.brpop(*@lists)
          # end
          _queue, job_args = Jiggler.redis_client.brpop(*@lists)
          @executor_pool.execute do
            begin
              parsed_args = JSON.parse(job_args)
              Jiggler.logger.info("Starting job: #{parsed_args.inspect}")
              job_class = Object.const_get(parsed_args["name"])
              job_class.new(**parsed_args["args"]).perform
              Jiggler.redis_client.call("incr", Jiggler.processed_counter)
              Jiggler.logger.info("Finished job: #{parsed_args.inspect}")
            rescue => e 
              Jiggler.redis_client.call("incr", Jiggler.failed_counter)
              Jiggler.logger.error(e.message)
              Jiggler.logger.error(e.backtrace.join("\n"))

              if parsed_args["retries"] && parsed_args["retries"] > 0 
                attempt = parsed_args["attempt"].nil? ? 0 : parsed_args["attempt"] 
                if attempt >= parsed_args["retries"]
                  Jiggler.logger.warn("Job failed after #{attempt} attempts: #{parsed_args.inspect}")
                else
                  attempt += 1
                  new_args = parsed_args.merge("attempt" => attempt)
                  Jiggler.logger.info("Retrying job: #{new_args.inspect}")
                  Jiggler.redis_client.lpush(Jiggler.retry_queue, new_args.to_json)
                end
              end
            end
          end
        end
      end
    end

    def cleanup
      Async { Jiggler.redis_client.call("srem", Jiggler.processes_set, @uuid) }
    end

    private

    def set_process_uuid
      Async { Jiggler.redis_client.call("sadd", Jiggler.processes_set, @uuid) }
    end

    def set_counters
      Async do
        processed_count = Jiggler.redis_client.call("get", Jiggler.processed_counter)
        Jiggler.redis_client.call("set", Jiggler.processed_counter, 0) unless processed_count
        failed_count = Jiggler.redis_client.call("get", Jiggler.failed_counter)
        Jiggler.redis_client.call("set", Jiggler.failed_counter, 0) unless failed_count
      end
    end
  end
end 
