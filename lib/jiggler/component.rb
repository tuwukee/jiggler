# frozen_string_literal: true

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
      Async(annotation: name) do
        watchdog(name, &block)
      end
    end

    def logger
      config.logger
    end

    def redis(async: true, &block)
      config.with_redis(async:, &block)
    end

    def tid
      return unless Async::Task.current?
      (Async::Task.current.object_id ^ ::Process.pid).to_s(36)
    end

    def hostname
      ENV["DYNO"] || Socket.gethostname
    end

    def process_nonce
      @@process_nonce ||= SecureRandom.hex(6)
    end

    def identity
      @@identity ||= "#{hostname}:#{::Process.pid}:#{process_nonce}"
    end
  end
end
