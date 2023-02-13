# frozen_string_literal: true

RSpec.describe Jiggler::AtLeastOnce::Acknowledger do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1,
      timeout: 1,
      poller_enabled: false,
      queues: ['fetcher_queue'],
      mode: :at_least_once
    )
  end
  let(:acknowledger) { Jiggler::AtLeastOnce::Acknowledger.new(config) }
  let(:job) { Jiggler::AtLeastOnce::Fetcher::CurrentJob.new(args: 'args', reserve_queue: 'ack_queue') }

  describe '#start' do
    it 'acks the job' do
      acknowledger.ack(job)
      expect(job).to receive(:ack)
      task = Async do
        Async do
          acknowledger.start
        end
        sleep(0.5)
        acknowledger.terminate
      end
      task.wait
    end
  end
end
