module Jiggler
  module Component
    attr_reader :config

    def handle_exception(ex, ctx = {})
      config.handle_exception(ex, ctx)
    end

    def watchdog(last_words)
      yield
    rescue Exception => ex
      handle_exception(ex, context: last_words)
      raise ex
    end

    def safe_async(name, &block)
      Async do
        Thread.current.name = name
        watchdog(name, &block)
      end
    end

    def logger
      config.logger
    end

    def redis(&block)
      config.with_redis(&block)
    end
  end
end
