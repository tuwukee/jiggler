# frozen_string_literal: true

require_relative "./jiggler/redis_store"
require_relative "./jiggler/config"
require "yaml"

module Jiggler
  VERSION = "0.1.0"

  def self.server?
    defined?(Jiggler::CLI)
  end

  def self.default_config
    @default_config ||= Jiggler::Config.new
  end

  def self.default_job_options
    @default_job_options ||= { "retry" => true, "queue" => Jiggler::Config::DEFAULT_QUEUE }
  end

  def self.logger
    default_config.logger
  end

  def self.configure_server
    yield default_config if server?
  end

  def self.configure_client
    yield default_config unless server?
  end

  def self.redis(async: true, &block)
    default_config.with_redis(async:, &block)
  end
  
  def self.list_prefix
    @list_prefix ||= "jiggler:list:"
  end

  def self.processes_set
    @processes_set ||= "jiggler:set:processes"
  end

  def self.processed_counter
    @processed_counter ||= "jiggler:counter:processed"
  end

  def self.failed_counter
    @failed_counter ||= "jiggler:counter:failed"
  end

  def self.processing_queue
    @processing_queue ||= "#{list_prefix}#{PROCESSING_QUEUE}"
  end

  def self.retry_queue
    @retry_queue ||= "#{list_prefix}#{RETRY_QUEUE}"
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
