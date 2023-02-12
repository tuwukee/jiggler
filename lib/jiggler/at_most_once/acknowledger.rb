module Jiggler
  module AtMostOnce
    class Acknowledger < BaseAcknowledger
      def ack(job)
        # noop
      end
  
      def start
        # noop
      end
      
      def wait
        # noop
      end
  
      def terminate
        # noop
      end
    end
  end
end
