# frozen_string_literal: true

require_relative "./jiggler/redis_store"
require "logger"
require "yaml"

module Jiggler
  DEFAULT_QUEUE = "default"
  PROCESSING_QUEUE = "processing"

  def self.default_job_options
    @default_job_options ||= {
      default_queue: DEFAULT_QUEUE,
      concurrency: 10,
      queues: [DEFAULT_QUEUE]
    }  
  end 
  
  def self.list_prefix
    @list_prefix ||= "jiggler:list:"
  end

  def self.processes_list
    @processes_list ||= "jiggler:processes"
  end

  def self.processing_queue
    @processing_queue ||= "#{list_prefix}#{PROCESSING_QUEUE}"
  end

  def self.redis_options=(options)
    @redis_client = Jiggler::RedisStore.new(options).client
  end

  def self.redis_client
    unless instance_variable_defined?(:@redis_client)
      @redis_client = Jiggler::RedisStore.new.client
    end

    @redis_client
  end

  def self.logger=(logger)
    @logger = logger
  end

  def self.logger
    @logger ||= Logger.new(STDOUT)
  end

  def self.logger_level=(level)
    logger.level = level
  end

  # TODO: read from args
  def self.config_path=(path)
    @config_path = File.expand_path(path)
  end

  def self.config_path 
    @config_path ||= File.expand_path("config/jiggler.yml")
  end

  def self.config
    @config ||= begin
      opts = Jiggler.default_job_options

      file_contents = begin
        File.read(config_path)
      rescue => e
        logger.warn("Could not read config file: #{e.message}")
        nil
      end

      if file_contents
        begin
          opts.merge!(YAML.safe_load(file_contents, permitted_classes: [Symbol], aliases: true))
        rescue => e
          logger.warn("Could not parse config file: #{e.message}")
        end
      end

      unless opts[:queues].include?(opts[:default_queue])
        opts[:queues] << opts[:default_queue]
      end

      opts[:lists] = opts[:queues].map do |q| 
        "#{list_prefix}#{q}" 
      end
      
      opts
    end
  end
end
