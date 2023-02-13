# frozen_string_literal: true

require_relative './lib/jiggler/version'

Gem::Specification.new do |s|
  s.name        = 'jiggler'
  s.version     = Jiggler::VERSION
  s.summary     = 'Ruby background job processor'
  s.description = 'Ruby background job processor using Redis and Async'
  s.authors     = ['Julija Alieckaja', 'Artsiom Kuts']
  s.email       = 'julija.alieckaja@gmail.com'
  s.homepage    = 'https://rubygems.org/gems/jiggler'
  s.license     = 'LGPL-3.0'
  
  s.executables   = ['jiggler']
  s.files         = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  s.test_files    = Dir['spec/**/*']
  s.require_paths = ['lib']

  s.metadata      = {
    'homepage_uri'    => 'https://github.com/tuwukee/jiggler',
    'changelog_uri'   => 'https://github.com/tuwukee/jiggler/blob/main/CHANGELOG.md',
    'source_code_uri' => 'https://github.com/tuwukee/jiggler',
    'bug_tracker_uri' => 'https://github.com/tuwukee/jiggler/issues'
  }

  s.add_dependency 'async', '~> 2.3'
  s.add_dependency 'async-io', '~> 1.34'
  s.add_dependency 'async-pool', '~> 0.3'
  s.add_dependency 'redis-client', '~> 0.12'
  s.add_dependency 'oj', '~> 3.14'
  s.add_dependency 'priority_queue_cxx', '~> 0.3'

  s.add_development_dependency 'bundler', '~> 2.4'
  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'rspec', '~> 3.12'
end
