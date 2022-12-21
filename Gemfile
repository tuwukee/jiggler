# frozen_string_literal: true

source "https://rubygems.org"

gem "rack"
gem "async", "~> 2.3"
gem "async-io"
gem "async-redis"
gem "redis-client"

group :development, :test do
  gem "debug", "~> 1.6"
  gem "rackup"
  gem "sidekiq" # for mem/speed comparison
  gem "ruby-prof"
  gem "heap-profiler"
end

group :test do
  gem "rspec"
end
