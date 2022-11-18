# frozen_string_literal: true

require_relative "./manager"
require_relative "./scheduled"
require_relative "./component"

module Jiggler
  class Launcher
    include Component

    def initialize(config)
      @done = false
      @uuid = SecureRandom.uuid
      @manager = Manager.new(config)
      @config = config
      # @scheduler = Scheduled::Poller.new(config)
    end

    def start
      set_process_uuid
      @manager.start
      # @scheduler.start
    end

    def quiet
      return if @done

      @done = true
      @manager.quite
      # @scheduler.terminate
    end

    def stop
      quiet
      @manager.terminate
    end

    def cleanup
      redis { |conn| conn.call("srem", Jiggler.processes_set, @uuid) }
    end

    def run_execution_loop
      loop do
        # TODO: use processing queue?
        # job_args = Jiggler.redis_client.brpoplpush(queue, Jiggler.processing_queue, 0)
        # job_args = {}
        # Jiggler.redis_client.transaction do |context|
          # queue, job_args = Jiggler.redis_client.brpop(*@lists)
        # end
        break cleanup if @done
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

    def set_process_uuid
      redis { |conn| conn.call("sadd", Jiggler.processes_set, @uuid) }
    end
  end
end
