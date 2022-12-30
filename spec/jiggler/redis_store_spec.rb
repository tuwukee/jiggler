# frozen_string_literal: true

RSpec.describe Jiggler::RedisStore do
  describe '#pool' do
    let(:options) { { concurrency: 4, async: true } }
    let(:redis_store) { described_class.new(options) }

    it 'returns an async pool' do
      expect(redis_store.pool).to be_a Async::Pool::Controller
    end

    context 'when connection is sync' do
      let(:options) { { concurrency: 4, async: false } }

      it 'returns a sync pool' do
        expect(redis_store.pool).to be_a RedisClient::Pooled
      end
    end
  end
end
