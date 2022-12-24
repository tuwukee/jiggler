# frozen_string_literal: true

module Jiggler
  class Retrier
    include Support::Component

    attr_reader :config, :collection

    def initialize(config, collection)
      @config = config
      @collection = collection
      @tid = tid
    end

    def wrapped(instance, parsed_job, queue)
      logger.info {
        "Starting #{instance.class.name} queue=#{instance.class.queue} tid=#{@tid} jid=#{parsed_job['jid']}"
      }
      yield
      logger.info { 
        "Finished #{instance.class.name} queue=#{instance.class.queue} tid=#{@tid} jid=#{parsed_job['jid']}"
      }
    rescue Async::Stop => stop
      raise stop
    rescue => err
      raise Async::Stop if exception_caused_by_shutdown?(err)

      process_retry(instance, parsed_job, queue, err)
      increase_failures_counter
      
      handle_exception(
        err,
        { 
          context: '\'Job raised exception\'',
          error_class: err.class.name,
          name: parsed_job['name'],
          queue: parsed_job['queue'],
          args: parsed_job['args'],
          attempt: parsed_job['attempt'],
          tid: @tid,
          jid: parsed_job['jid']
        }
      )
    end

    private

    def process_retry(jobinst, parsed_job, queue, exception)
      job_class = jobinst.class
      max_retry_attempts = job_class.retries.to_i 
      count = parsed_job['attempt'].to_i + 1

      message = exception_message(exception)
      if message.respond_to?(:scrub!)
        message.force_encoding('utf-8')
        message.scrub!
      end

      parsed_job['error_message'] = message
      parsed_job['error_class'] = exception.class.name
      parsed_job['queue'] = job_class.retry_queue
      parsed_job['started_at'] ||= Time.now.to_f

      return retries_exhausted(jobinst, parsed_job, exception) if count >= max_retry_attempts

      jitter = rand(10) * (count + 1)
      delay = count**4 + 15
      retry_at = Time.now.to_f + delay + jitter
      parsed_job['retry_at'] = retry_at
      if count > 1
        parsed_job['retried_at'] = Time.now.to_f
      end
      parsed_job['attempt'] = count
      payload = JSON.generate(parsed_job)

      config.with_async_redis do |conn|
        conn.call('ZADD', config.retries_set, retry_at.to_s, payload)
      end
    end

    def retries_exhausted(jobinst, parsed_job, exception)
      logger.debug('Retrier') { 
        "Retries exhausted for #{parsed_job['name']} jid=#{parsed_job['jid']}" 
      }

      send_to_morgue(parsed_job)
    end

    def send_to_morgue(parsed_job)
      logger.warn('Retrier') { 
        "#{parsed_job['name']} has been sent to dead jid=#{parsed_job['jid']}"
      }
      payload = JSON.generate(parsed_job)
      now = Time.now.to_f

      config.with_async_redis do |conn|
        conn.multi do |xa|
          xa.call('ZADD', config.dead_set, now.to_s, payload)
          xa.call('ZREMRANGEBYSCORE', config.dead_set, '-inf', now - config[:dead_timeout])
          xa.call('ZREMRANGEBYRANK', config.dead_set, 0, - config[:max_dead_jobs])
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

    def increase_failures_counter
      return unless config[:stats_enabled]
      collection.data[:failures] += 1
    end

    def exception_message(exception)
      # Message from app code
      exception.message.to_s[0, 10_000]
    rescue
      'Exception message unavailable'
    end
  end
end
