# frozen_string_literal: true

RSpec.describe Jiggler::Retrier do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1, 
      timeout: 1, 
      verbose: true,
      queues: ['test'],
      redis_mode: :async
    ) 
  end
  let(:collection) { Jiggler::Stats::Collection.new('test-retrier-uuid') }
  let(:retrier) { Jiggler::Retrier.new(config, collection) }

  describe '#wrapped' do
    context 'failed jobs' do
      let(:job) { MyFailedJob.new }

      it 'increments attempt if mex retries are not reached' do
        msg = { 'jid' => '1' }
        config.cleaner.prune_failures_counter
        expect(config.logger).to receive(:error).twice
        retrier.wrapped(job, msg, 'test') do
          job.perform
        end
        expect(msg['attempt']).to be 1
        expect(msg['error_message']).to eq 'Oh no!'
        expect(msg['error_class']).to eq 'StandardError'
        expect(collection.data[:failures]).to be 1
      end

      it 'does not increment attempt if max retries are reached' do
        msg = { 'attempt' => 3, 'jid' => '123', 'name' => 'MyFailedJob' }
        config.cleaner.prune_failures_counter
        expect(config.logger).to receive(:error).twice
        retrier.wrapped(job, msg, 'test') do
          job.perform
        end

        expect(msg['attempt']).to be 3
        expect(msg['error_message']).to eq 'Oh no!'
        expect(msg['error_class']).to eq 'StandardError'
        expect(collection.data[:failures]).to be 1
      end
    end

    context 'successful jobs' do
      it 'does not throw any exceptions' do
        msg = { 'jid' => '2' }
        expect(config.logger).to_not receive(:error)
        retrier.wrapped(MyJob.new, msg, 'default') { 'success' }
        expect(collection.data[:failures]).to be 0
      end
    end
  end
end
