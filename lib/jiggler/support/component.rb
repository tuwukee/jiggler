# frozen_string_literal: true

module Jiggler
  module Support
    module Component
      attr_reader :config
  
      def handle_exception(ex, ctx = {}, raise_ex: false)
        config.handle_exception(ex, ctx, raise_ex: raise_ex)
      end
  
      def watchdog(last_words)
        yield
      rescue Exception => ex
        handle_exception(ex, { context: last_words, tid: tid }, raise_ex: true)
      end
  
      def safe_async(name, &block)
        Async(annotation: name) do
          watchdog(name, &block)
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
