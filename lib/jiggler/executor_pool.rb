# frozen_string_literal: true

require "async"

require "async/pool/controller"
require "async/pool/resource"

module Jiggler
  class ExecutorPool
    def initialize(size:)
      @size = size
    end
  
    def execute(&block)
      Async do
        pool.acquire do |resource|
          block.call
        end
      end      
    end

    private

    def pool
      @pool ||= Async::Pool::Controller.new(Async::Pool::Resource, concurrency: @size, limit: @size)
    end
  end
end
  