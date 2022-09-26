# frozen_string_literal: true

require "async"
require_relative "./executor_pool"
require_relative "./jobs_temp"

module Jiggler
  class Launcher
    attr_reader :queues, :processing_queue

    def initialize
      @lists = Jiggler.config[:lists] 
      @executor_pool = Jiggler::ExecutorPool.new(size: 10)
    end

    def run
      Async do
        loop do
          # TODO: use processing queue?
          # job_args = Jiggler.redis_client.brpoplpush(queue, Jiggler.processing_queue, 0)
          _queue, job_args = Jiggler.redis_client.brpop(*@lists)
          @executor_pool.execute do 
            puts "Executing job in a block"
            begin
              parsed_args = JSON.parse(job_args)
              job_class = Object.const_get(parsed_args["name"])
              job_class.new(**parsed_args["args"]).perform
            rescue => e 
              puts "Exception: #{e.message}\n#{e.backtrace}"
              # TODO: mark the job as failed
            end
          end
        end
      end
    end
  end
end 
