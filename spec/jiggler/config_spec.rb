# frozen_string_literal: true

RSpec.describe Jiggler::Config do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1, 
      client_concurrency: 1,
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
      expect(config[:client_async]).to be false
    end
    
    context 'for prefixed queues' do
      it 'generates prefixes' do
        expect(config.prefixed_queues.keys).to eq ['jiggler:list:test', 'jiggler:list:test2']
        expect(config.prefixed_queues.values).to eq [0, 1]
        expect(config.sorted_prefixed_queues).to eq ['jiggler:list:test', 'jiggler:list:test2']
      end

      context 'when queues are not specified' do
        let(:config) { Jiggler::Config.new }
        it 'sets default queue' do
          expect(config.prefixed_queues.keys).to eq ['jiggler:list:default']
          expect(config.prefixed_queues.values).to eq [0]
          expect(config.sorted_prefixed_queues).to eq ['jiggler:list:default']
        end
      end

      context 'when quesues are specified as hash' do
        let(:config) { Jiggler::Config.new(queues: { test: 4, test2: 1 }) }
        it 'respects priority' do
          expect(config.prefixed_queues.keys).to eq ['jiggler:list:test', 'jiggler:list:test2']
          expect(config.prefixed_queues.values).to eq [4, 1]
          expect(config.sorted_prefixed_queues).to eq ['jiggler:list:test2', 'jiggler:list:test']
        end
      end
    end

    it 'gets redis options for server' do
      expect(config.redis_options).to eq(
        concurrency: 4,
        async: true,
        redis_url: 'redis://localhost:6379'
      )
    end

    it 'gets redis options for client' do
      expect(config.client_redis_options).to eq(
        concurrency: 1,
        async: false,
        client_redis_pool: nil,
        redis_url: 'redis://localhost:6379'
      )
    end
  end
end
