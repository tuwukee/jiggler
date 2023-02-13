# frozen_string_literal: true

source 'https://rubygems.org'

gem 'rack'
gem 'redis-client'
gem 'oj'
gem 'async'
gem 'async-io'
gem 'async-pool'
gem 'priority_queue_cxx'

group :development, :test do
  gem 'debug'
end

group :development do
  gem 'rackup'
  gem 'sidekiq' # for mem/speed comparison
  gem 'ruby-prof'
  gem 'heap-profiler'
  gem 'falcon'
  gem 'sinatra', '~> 2.0.0.beta2'
end

group :test do
  gem 'rspec'
end
