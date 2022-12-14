# frozen_string_literal: true

RSpec.describe Jiggler::Config do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1, 
      environment: 'test',
      timeout: 1, 
      verbose: true,
      queues: ['test', 'test2'],
      require: 'test.rb',
      max_dead_jobs: 100,
      dead_timeout: 100,
      redis_url: 'redis://localhost:6379'
    ) 
  end

  describe '#initialize' do
    it 'sets correct attrs' do
      expect(config[:concurrency]).to be 1
      expect(config[:environment]).to eq 'test'
      expect(config[:timeout]).to be 1
      expect(config[:verbose]).to be true
      expect(config[:queues]).to eq ['test', 'test2']
      expect(config[:require]).to eq 'test.rb'
      expect(config[:max_dead_jobs]).to be 100
      expect(config[:dead_timeout]).to be 100
      expect(config[:stats_interval]).to be 10
      expect(config[:poller_enabled]).to be true
      expect(config[:poll_interval]).to be 5
      expect(config[:server_mode]).to be false
    end

    it 'generates prefixed queues' do
      expect(config.prefixed_queues).to eq ['jiggler:list:test', 'jiggler:list:test2']
    end

    it 'gets redis options for server' do
      config[:server_mode] = true
      expect(config.redis_options).to eq(
        concurrency: 4,
        redis_pool: nil,
        async: true,
        redis_url: 'redis://localhost:6379'
      )
    end

    it 'gets redis options for client' do
      config[:server_mode] = false
      expect(config.redis_options).to eq(
        concurrency: 1,
        redis_pool: nil,
        redis_url: 'redis://localhost:6379'
      )
    end
  end
end
