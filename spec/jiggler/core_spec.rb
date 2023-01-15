# frozen_string_literal: true

RSpec.describe 'Core' do
  describe '.configure' do
    it 'applies the configuration' do
      Jiggler.configure do |config|
        config[:concurrency] = 1
        config[:client_concurrency] = 2
        config[:timeout] = 3
        config[:stats_interval] = 4
        config[:max_dead_jobs] = 5
        config[:dead_timeout] = 6
        config[:poll_interval] = 7
        config[:poller_enabled] = false
        config[:client_async] = true
        config[:queues] = %w[foo bar]
        config[:require] = 'foo'
        config[:environment] = 'bar'
      end
      expect(Jiggler.config[:concurrency]).to be 1
      expect(Jiggler.config[:client_concurrency]).to be 2
      expect(Jiggler.config[:timeout]).to be 3
      expect(Jiggler.config[:stats_interval]).to be 4
      expect(Jiggler.config[:max_dead_jobs]).to be 5
      expect(Jiggler.config[:dead_timeout]).to be 6
      expect(Jiggler.config[:poll_interval]).to be 7
      expect(Jiggler.config[:poller_enabled]).to be false
      expect(Jiggler.config[:client_async]).to be true
      expect(Jiggler.config[:queues]).to eq %w[foo bar]
      expect(Jiggler.config[:require]).to eq 'foo'
      expect(Jiggler.config[:environment]).to eq 'bar'
    end
  end
end
