# frozen_string_literal: true

RSpec.describe Jiggler::RedisStore do
  describe '#pool' do
    let(:options) { { concurrency: 4, redis_mode: :async } }
    let(:redis_store) { described_class.new(options) }

    it 'returns an async pool' do
      expect(redis_store.pool).to be_a Async::Pool::Controller
    end

    context 'when redis_mode is :sync' do
      let(:options) { { concurrency: 4, redis_mode: :sync } }

      it 'returns a sync pool' do
        expect(redis_store.pool).to be_a ConnectionPool
      end
    end

    context 'when redis_pool is provided' do
      let(:options) { { concurrency: 4, redis_mode: :sync, redis_pool: :pool } }

      it 'returns the provided pool' do
        expect(redis_store.pool).to be :pool
      end
    end
  end
end
