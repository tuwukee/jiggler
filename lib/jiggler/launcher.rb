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
              Jiggler.logger.info("Finished job: #{parsed_args.inspect}")
            rescue => e 
              Jiggler.logger.error(e.message)
              Jiggler.logger.error(e.backtrace.join("\n"))
              # TODO: mark the job as failed
            end
          end
        end
      end
    end

    def cleanup
      Async { Jiggler.redis_client.call("srem", Jiggler.processes_list, @uuid) }
    end

    private

    def set_process_uuid
      Async { Jiggler.redis_client.call("sadd", Jiggler.processes_list, @uuid) }
    end
  end
end 
