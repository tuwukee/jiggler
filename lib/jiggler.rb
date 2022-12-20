# frozen_string_literal: true

require_relative "./jiggler/support/component"
require_relative "./jiggler/scheduled/enqueuer"
require_relative "./jiggler/scheduled/poller"
require_relative "./jiggler/stats/collection"
require_relative "./jiggler/stats/monitor"

require_relative "./jiggler/errors"
require_relative "./jiggler/redis_store"
require_relative "./jiggler/job"
require_relative "./jiggler/config"
require_relative "./jiggler/cleaner"
require_relative "./jiggler/retrier"
require_relative "./jiggler/launcher"
require_relative "./jiggler/manager"
require_relative "./jiggler/worker"
require_relative "./jiggler/summary"
require_relative "./jiggler/cli"

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

  def self.redis(async: false, &block)
    config.with_redis(async:, &block)
  end

  def self.summary
    Jiggler::Summary.all
  end
end
