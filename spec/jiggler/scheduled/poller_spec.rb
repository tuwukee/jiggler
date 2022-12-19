# frozen_string_literal: true

RSpec.describe Jiggler::Scheduled::Poller do
  let(:config) { Jiggler::Config.new(concurrency: 1, timeout: 1, verbose: true, poll_interval: 1) }
  let(:poller) { described_class.new(config) }

  describe "#start" do
    it "starts the poller" do
      task = Async do
        expect(poller).to receive(:initial_wait)
        expect(poller).to receive(:enqueue).at_least(:once).and_call_original
        Async { poller.start }
        expect(poller.instance_variable_get(:@done)).to be false
        sleep(1)
        poller.terminate
      end
      task.wait
    end
  end

  describe "#terminate" do 
    it "terminates the poller" do
      expect(poller.instance_variable_get(:@enqueuer)).to receive(:terminate).
        and_call_original
      task = Async do
        Async { poller.start }
        sleep(1)
        poller.terminate
        expect(poller.instance_variable_get(:@done)).to be true
      end
      task.wait
    end
  end
end
