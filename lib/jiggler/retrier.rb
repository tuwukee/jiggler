# frozen_string_literal: true

require "zlib"
require "base64"

module Jiggler
  module Retry
    class Handled < ::RuntimeError; end

    class Retrier
      include Component
  
      DEFAULT_MAX_RETRY_ATTEMPTS = 25

      def new(config)
        @config = config
        @max_retries = Jiggler.config[:max_retries] || DEFAULT_MAX_RETRY_ATTEMPTS
      end

      def wrapped(instance, msg, queue)
        yield
      rescue Handled => ex
        raise ex
      rescue Async::Stop => stop
        raise stop
      rescue => err
        raise Async::Stop if exception_caused_by_shutdown?(e)

        if msg["retry"].nil?
          msg["retry"] = instance.class.get_jiggler_options["retry"]
        end

        raise err unless msg["retry"]
        process_retry(instance, msg, queue, err)
        # We've handled this error associated with this job, don't
        # need to handle it at the global level
        raise Handled
      end

      private

      def process_retry(jobinst, msg, queue, exception)
        max_retry_attempts = retry_attempts_from(msg["retry"], @max_retries)
  
        msg["queue"] = (msg["retry_queue"] || queue)
  
        m = exception_message(exception)
        if m.respond_to?(:scrub!)
          m.force_encoding("utf-8")
          m.scrub!
        end
  
        msg["error_message"] = m
        msg["error_class"] = exception.class.name
        count = if msg["retry_count"]
          msg["retried_at"] = Time.now.to_f
          msg["retry_count"] += 1
        else
          msg["failed_at"] = Time.now.to_f
          msg["retry_count"] = 0
        end
  
        if msg["backtrace"]
          lines = if msg["backtrace"] == true
            exception.backtrace
          else
            exception.backtrace[0...msg["backtrace"].to_i]
          end
  
          msg["error_backtrace"] = compress_backtrace(lines)
        end
  
        # Goodbye dear message, you (re)tried your best I'm sure.
        return retries_exhausted(jobinst, msg, exception) if count >= max_retry_attempts
  
        strategy, delay = delay_for(jobinst, count, exception)
        case strategy
        when :discard
          return # poof!
        when :kill
          return retries_exhausted(jobinst, msg, exception)
        end
  
        # Logging here can break retries if the logging device raises ENOSPC #3979
        # logger.debug { "Failure! Retry #{count} in #{delay} seconds" }
        jitter = rand(10) * (count + 1)
        retry_at = Time.now.to_f + delay + jitter
        payload = JSON.generate(msg)
        redis do |conn|
          conn.zadd("retry", retry_at.to_s, payload)
        end
      end
  
      # returns (strategy, seconds)
      def delay_for(jobinst, count, exception)
        rv = begin
          # sidekiq_retry_in can return two different things:
          # 1. When to retry next, as an integer of seconds
          # 2. A symbol which re-routes the job elsewhere, e.g. :discard, :kill, :default
          jobinst&.jiggler_retry_in_block&.call(count, exception)
        rescue Exception => e
          handle_exception(e, {context: "Failure scheduling retry using the defined `jiggler_retry_in` in #{jobinst.class.name}, falling back to default"})
          nil
        end
  
        delay = (count**4) + 15
        if Integer === rv && rv > 0
          delay = rv
        elsif rv == :discard
          return [:discard, nil] # do nothing, job goes poof
        elsif rv == :kill
          return [:kill, nil]
        end
  
        [:default, delay]
      end
  
      def retries_exhausted(jobinst, msg, exception)
        begin
          block = jobinst&.jiggler_retries_exhausted_block
          block&.call(msg, exception)
        rescue => e
          handle_exception(e, {context: "Error calling retries_exhausted", job: msg})
        end
  
        send_to_morgue(msg) unless msg["dead"] == false

        # todo: add on_death custom handling
      end
  
      def send_to_morgue(msg)
        logger.info { "Adding dead #{msg["class"]} job #{msg["jid"]}" }
        payload = JSON.generate(msg)
        now = Time.now.to_f
  
        redis do |conn|
          conn.multi do |xa|
            xa.zadd("dead", now.to_s, payload)
            xa.zremrangebyscore("dead", "-inf", now - config[:dead_timeout_in_seconds])
            xa.zremrangebyrank("dead", 0, - config[:dead_max_jobs])
          end
        end
      end
  
      def retry_attempts_from(msg_retry, default)
        if msg_retry.is_a?(Integer)
          msg_retry
        else
          default
        end
      end
  
      def exception_caused_by_shutdown?(e, checked_causes = [])
        return false unless e.cause
  
        # Handle circular causes
        checked_causes << e.object_id
        return false if checked_causes.include?(e.cause.object_id)
  
        e.cause.instance_of?(Async::Stop) ||
          exception_caused_by_shutdown?(e.cause, checked_causes)
      end
  
      # Extract message from exception.
      # Set a default if the message raises an error
      def exception_message(exception)
        # App code can stuff all sorts of crazy binary data into the error message
        # that won't convert to JSON.
        exception.message.to_s[0, 10_000]
      rescue
        +"!!! ERROR MESSAGE THREW AN ERROR !!!"
      end
  
      def compress_backtrace(backtrace)
        serialized = JSON.generate(backtrace)
        compressed = Zlib::Deflate.deflate(serialized)
        Base64.encode64(compressed)
      end
    end
  end
end
