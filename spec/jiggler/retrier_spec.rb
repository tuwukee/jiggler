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
  let(:retrier) { Jiggler::Retrier.new(config) }

  describe '#wrapped' do
    context 'failed jobs' do
      let(:job) { MyFailedJob.new }

      it 'retries if mex retries are not reached' do
        msg = {}
        expect do
          retrier.wrapped(job, msg, 'test') do
            job.perform
          end
        end.to raise_error(Jiggler::RetryHandled)
        expect(msg['attempt']).to be 1
      end

      it 'does not retry if max retries are reached' do
        msg = { 'attempt' => 3, 'jid' => '123', 'name' => 'MyFailedJob' }
        expect do
          retrier.wrapped(job, msg, 'test') do
            job.perform
          end
        end.to raise_error(Jiggler::RetryHandled)

        expect(msg['attempt']).to be 3
        expect(msg['error_message']).to eq 'Oh no!'
        expect(msg['error_class']).to eq 'StandardError'
      end
    end

    context 'successful jobs' do
      it 'does not throw any exceptions' do
        expect do
          result = retrier.wrapped(MyJob.new, {}, 'default') { 'success' }
          expect(result).to eq('success')
        end.not_to raise_error
      end
    end
  end
end
