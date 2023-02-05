# frozen_string_literal: true

module Jiggler
  class Acknowledger
    include Support::Helper

    def initialize(config)
      @config = config
      @queue = Queue.new
    end

    def ack(job)
      @queue.push(job)
    end

    def start
      @runner = safe_async('Acknowledger') do
        while (job = @queue.pop) != nil
          begin
            job.ack
          rescue StandardError => err
            log_error(err, context: '\'Could not acknowledge a job\'', job: job)
          end
        end
      end
    end
    
    def wait
      @runner&.wait
    end

    def terminate
      @queue.close
    end
  end
end
