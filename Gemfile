# frozen_string_literal: true

source 'https://rubygems.org'

gem 'rack'
gem 'async'
gem 'async-io'
gem 'async-pool'
gem 'redis-client'
gem 'oj'

group :development, :test do
  gem 'debug', '~> 1.6'
  gem 'rackup'
  gem 'sidekiq' # for mem/speed comparison
  gem 'ruby-prof'
  gem 'heap-profiler'
end

group :test do
  gem 'rspec'
end
