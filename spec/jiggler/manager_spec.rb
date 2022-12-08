# frozen_string_literal: true

RSpec.describe Jiggler::Manager do
  let(:config) { Jiggler::Config.new(concurrency: 4, timeout: 3, verbose: true) }
  let(:manager) { described_class.new(config) }

  it { expect(manager.instance_variable_get(:@workers).count).to be 4 }

  describe "#start" do
    after { manager.quite }

    it "starts the manager" do
      expect(manager.instance_variable_get(:@workers)).to all(receive(:run))
      manager.start
    end
  end

  describe "#quite" do
    it "quits the manager" do
      expect(manager.instance_variable_get(:@workers)).to all(receive(:quite).and_call_original)
      task = Async do
        manager.start
        manager.quite
        expect(manager.instance_variable_get(:@done)).to be true
      end
      task.wait
    end
  end

  describe "#terminate" do
    it "terminates the manager" do
      expect(manager.instance_variable_get(:@workers)).to all(receive(:quite).and_call_original)
      expect(manager.instance_variable_get(:@workers)).to all(receive(:terminate).and_call_original)
      task = Async do
        manager.start
        manager.terminate
        expect(manager.instance_variable_get(:@done)).to be true
      end
      task.wait
    end
  end
end
