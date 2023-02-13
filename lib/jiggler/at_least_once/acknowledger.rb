# frozen_string_literal: true

module Jiggler
  module AtLeastOnce
    class Acknowledger < BaseAcknowledger
      def initialize(config)
        super
        @runners = []
        @queue = Queue.new
      end

      def ack(job)
        @queue.push(job)
      end
  
      def start
        @config[:concurrency].times do
          @runners << safe_async('Acknowledger') do
            while (job = @queue.pop) != nil
              begin
                job.ack
              rescue StandardError => err
                log_error(err, context: '\'Could not acknowledge a job\'', job: job)
              end
            end
            logger.debug('Acknowledger exits')
          rescue Async::Stop
            logger.debug('Acknowledger received stop signal')
          end
        end
      end
      
      def wait
        @runners.each(&:wait)
      end
  
      def terminate
        logger.debug('Suspending the acknowledger')
        @queue.close
      end
    end
  end
end
