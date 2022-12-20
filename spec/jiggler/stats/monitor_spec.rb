# frozen_string_literal: true

RSpec.describe Jiggler::Stats::Monitor do
  let(:config) { Jiggler::Config.new(timeout: 1, verbose: true, stats_interval: 1) }
  let(:collection) { Jiggler::Stats::Collection.new("monitoring-uuid") }
  let(:monitor) { described_class.new(config, collection) }

  describe "#start" do
    it "starts the monitor" do
      task = Async do
        expect(monitor).to receive(:load_data_into_redis).at_least(:once).and_call_original
        Async { monitor.start }
        expect(monitor.instance_variable_get(:@done)).to be false
        sleep(1)
        monitor.terminate
      end
      task.wait
    end
  end

  describe "#terminate" do
    it "terminates the monitor" do
      task = Async do
        Async { monitor.start }
        sleep(1)
        expect(monitor).to receive(:cleanup).and_call_original
        monitor.terminate
        expect(monitor.instance_variable_get(:@done)).to be true
      end
      task.wait
    end
  end
end
