# frozen_string_literal: true

module Jiggler
  class Retrier
    include Support::Component

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def wrapped(instance, msg, queue)
      yield
    rescue Async::Stop => stop
      raise stop
    rescue => err
      raise Async::Stop if exception_caused_by_shutdown?(err)

      process_retry(instance, msg, queue, err)
      
      # exception is handled, so we can raise this to stop the worker
      raise Jiggler::RetryHandled
    end

    private

    def process_retry(jobinst, msg, queue, exception)
      job_class = jobinst.class
      max_retry_attempts = job_class.retries.to_i 
      count = msg["attempt"].to_i + 1

      message = exception_message(exception)
      if message.respond_to?(:scrub!)
        message.force_encoding("utf-8")
        message.scrub!
      end

      msg["error_message"] = message
      msg["error_class"] = exception.class.name
      msg["queue"] = job_class.retry_queue
      msg["class"] = job_class.name
      msg["started_at"] ||= Time.now.to_f

      return retries_exhausted(jobinst, msg, exception) if count >= max_retry_attempts

      jitter = rand(10) * (count + 1)
      delay = count**4 + 15
      retry_at = Time.now.to_f + delay + jitter
      msg["retry_at"] = retry_at
      if count > 1
        msg["retried_at"] = Time.now.to_f
      end
      msg["attempt"] = count
      payload = JSON.generate(msg)

      redis do |conn|
        conn.zadd(config.retries_set, retry_at.to_s, payload)
      end
    end

    def retries_exhausted(jobinst, msg, exception)
      logger.warn("Retries exhausted for #{msg["class"]} tid=#{tid} jid=#{msg["jid"]}")

      send_to_morgue(msg)
    end

    # todo: review this
    def send_to_morgue(msg)
      logger.warn("#{msg["class"]} has been sent to dead tid=#{tid} jid=#{msg["jid"]}")
      payload = JSON.generate(msg)
      now = Time.now.to_f

      redis do |conn|
        conn.multi do |xa|
          xa.zadd(config.dead_set, now.to_s, payload)
          xa.zremrangebyscore(config.dead_set, "-inf", now - config[:dead_timeout])
          xa.zremrangebyrank(config.dead_set, 0, - config[:max_dead_jobs])
        end
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

    def exception_message(exception)
      # Message from app code
      exception.message.to_s[0, 10_000]
    rescue
      "Exception message unavailable"
    end
  end
end
