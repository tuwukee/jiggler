# frozen_string_literal: true

module Jiggler
  module Support
    module Helper
      attr_reader :config
  
      def handle_exception(ex, ctx = {})
        config.handle_exception(ex, ctx)
      end
  
      def safe_async(name)
        Async do
          yield
        rescue Exception => ex
          handle_exception(ex, { context: name, tid: tid })        
        end
      end
  
      def logger
        config.logger
      end
  
      def tid
        return unless Async::Task.current?
        (Async::Task.current.object_id ^ ::Process.pid).to_s(36)
      end
    end
  end
end
