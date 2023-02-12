# frozen_string_literal: true

require 'debug'

# client
require 'jiggler'
require 'jiggler/web'

# server
require 'jiggler/support/helper'
require 'jiggler/scheduled/enqueuer'
require 'jiggler/scheduled/poller'
require 'jiggler/stats/collection'
require 'jiggler/stats/monitor'
require 'jiggler/errors'
require 'jiggler/retrier'
require 'jiggler/launcher'
require 'jiggler/manager'
require 'jiggler/base_acknowledger'
require 'jiggler/base_fetcher'
require 'jiggler/at_most_once/acknowledger'
require 'jiggler/at_most_once/fetcher'
require 'jiggler/at_least_once/acknowledger'
require 'jiggler/at_least_once/fetcher'
require 'jiggler/worker'
require 'jiggler/cli'

require_relative './fixtures/jobs'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  config.around(:each) do |example|
    Timeout.timeout(10) do
      example.run
    end
  end

  config.profile_examples = 10
  config.order = :random

  Kernel.srand config.seed
end
