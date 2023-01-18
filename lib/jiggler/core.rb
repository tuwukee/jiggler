# frozen_string_literal: true

require 'oj'
require 'securerandom'

# namespace methods
module Jiggler  
  def self.config
    @config ||= Jiggler::Config.new
  end

  def self.logger
    config.logger
  end

  def self.configure(&block)
    block.call(config)
  end

  def self.summary
    config.summary.all
  end
end
