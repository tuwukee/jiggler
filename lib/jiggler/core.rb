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

  def self.configure_server(&block)
    @server_blocks ||= []
    @server_blocks << block
  end

  def self.run_configuration
    if server?
      return if @server_blocks.nil?
      @server_blocks.each { |block| block.call(config) }
    else
      return if @client_blocks.nil?
      @client_blocks.each { |block| block.call(config) }
    end
  end

  def self.configure_client(&block)
    @client_blocks ||= []
    @client_blocks << block
  end

  def self.summary
    config.summary.all
  end
end
