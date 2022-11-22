# frozen_string_literal: true

require_relative "./jiggler/redis_store"
require_relative "./jiggler/config"
require "yaml"

module Jiggler
  VERSION = "0.1.0"

  def self.server?
    defined?(Jiggler::CLI)
  end
  
  def self.config
    @config ||= Jiggler::Config.new
  end

  def self.logger
    config.logger
  end

  def self.configure_server
    yield config if server?
  end

  def self.configure_client
    yield config unless server?
  end

  def self.redis(async: true, &block)
    config.with_redis(async:, &block)
  end
end
