# frozen_string_literal: true

require 'oj'

module Jiggler
  def self.server?
    config[:server_mode] == true
  end
  
  def self.config
    @config ||= Jiggler::Config.new
  end

  def self.logger
    config.logger
  end

  def self.configure(&block)
    block.call(config)
  end

  def self.summary(pool: nil)
    config.summary.all(pool: pool)
  end
end
