# frozen_string_literal: true

module Jiggler
  module Support
    module Helper
      def safe_async(name)
        Async do
          yield
        rescue Exception => ex
          log_error(ex, context: name, tid: tid)
        end
      end

      def log_error(ex, **ctx)
        err_context = ctx.compact.map { |k, v| "#{k}=#{v}" }.join(' ')
        logger.error("error_message='#{ex.message}' #{err_context}")
        logger.error(ex.backtrace.first(12).join("\n")) unless ex.backtrace.nil?
      end

      def log_error_short(err, **ctx)
        err_context = ctx.compact.map { |k, v| "#{k}=#{v}" }.join(' ')
        logger.error("error_message='#{err.message}' #{err_context}")
      end
  
      def logger
        @config.logger
      end

      def scan_all(mask)
        @config.with_sync_redis do |conn|
          start = '0'
          all_keys = []
          loop do
            start, keys = conn.call('SCAN', start, 'MATCH', mask)
            break if keys.empty?
            all_keys += keys
            break if start == '0'
          end
          all_keys
        end
      end
  
      def tid
        return unless Async::Task.current?
        (Async::Task.current.object_id ^ ::Process.pid).to_s(36)
      end
    end
  end
end
