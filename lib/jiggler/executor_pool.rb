# frozen_string_literal: true

require "async"

require "async/pool/controller"
require "async/pool/resource"

module Jiggler
  class ExecutorPool
    def initialize(concurrency:)
      @concurrency = concurrency
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
      @pool ||= Async::Pool::Controller.new(
        Async::Pool::Resource,
        concurrency: @concurrency, 
        limit: @concurrency
      )
    end
  end
end
  