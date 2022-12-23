# frozen_string_literal: true

require 'jiggler/support/component'
require 'jiggler/scheduled/enqueuer'
require 'jiggler/scheduled/poller'
require 'jiggler/stats/collection'
require 'jiggler/stats/monitor'

require 'jiggler/errors'
require 'jiggler/redis_store'
require 'jiggler/job'
require 'jiggler/config'
require 'jiggler/cleaner'
require 'jiggler/retrier'
require 'jiggler/launcher'
require 'jiggler/manager'
require 'jiggler/worker'
require 'jiggler/summary'
require 'jiggler/version'

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
