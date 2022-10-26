module Jiggler
  class Worker
    TIMEOUT = 5

    Job = Struct.new(:queue, :args, keyword_init: true)

    attr_reader :current_job

    def initialize(**options)
      @done = false
      @current_job = nil
      @callback = options[:callback]
      @config = options[:config]
    end

    def run
      @runner = Async do
        loop do
          break @callback.call(self) if @done
          process_job
        rescue Async::Stop
          cleanup
          @callback.call(self)
        rescue => ex
          @callback.call(self, ex)
        end
      end
    end

    def terminate
      @done = true
      @runner&.stop
    end

    def quite
      @done = true
    end

    private

    def process_job
      @current_job = fetch_one
      return if current_job.nil? # timed out brpop or done
      execute_job
      @current_job = nil
    end

    def fetch_one
      queue, args = redis.brpop(*queues)
      if queue
        if @done
          requeue(queue, job_args)
          nil
        else
          Job.new(queue:, args:)
        end
      end
    rescue Async::Stop
    rescue => ex
      handle_fetch_error(ex)
    end
    
    def execute_job
      parsed_args = JSON.parse(current_job.args)
    rescue JSON::ParserError
      send_to_dead
    rescue => ex
      

    def requeue(queue, args)
      # todo
    end

    def handle_fetch_error(ex)
      # pass
    end

    def cleanup
      @callback.call(self)
    end

    def redis
      @redis ||= @config[:redis]
    end

    def queues
      @queues ||= [
        *@config[:lists].uniq, { timeout: TIMEOUT }
      ]
    end

    def constantize(str)
      return Object.const_get(str) unless str.include?("::")

      names = str.split("::")
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        # the false flag limits search for name to under the constant namespace
        #   which mimics Rails' behaviour
        constant.const_get(name, false)
      end
    end
  end
end