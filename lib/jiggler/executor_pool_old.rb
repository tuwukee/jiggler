# frozen_string_literal: true

module Jiggler
  class ExecutorPool
    def initialize(size:)
      @size = size
      @pool = SizedQueue.new(size)
      size.times { @pool << 1 }
      @mutex = Mutex.new
      @running_executors = []
    end

    def execute(&block)
      @pool.pop
      @mutex.synchronize do
        ractor = Ractor.new do
          puts "Ractor starts: #{self.inspect}"
          block_in_ractor = Ractor.receive
          begin
            block_in_ractor.call
          rescue Exception => e
            puts "Exception: #{e.message}\n#{e.backtrace}"
          ensure
            @pool << 1
          end
        end
        ractor.send(block)
        @running_executors << ractor
      end        
    end
  end
end
