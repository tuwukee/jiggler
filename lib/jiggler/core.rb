# frozen_string_literal: true

module Jiggler
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

  def self.redis(async: false, &block)
    config.with_redis(async:, &block)
  end

  def self.summary
    Jiggler::Summary.all
  end
end
