# frozen_string_literal: true

RSpec.describe Jiggler::Manager do
  let(:config) do 
    Jiggler::Config.new(
      concurrency: 4,
      timeout: 1,
      server_mode: true
    )
  end
  let(:collection) { Jiggler::Stats::Collection.new(config) }
  let(:manager) { described_class.new(config, collection) }

  it { expect(manager.instance_variable_get(:@workers).count).to be 4 }

  describe '#start' do
    it 'starts the manager' do
      expect(manager.instance_variable_get(:@workers)).to all(receive(:run))
      Async { manager.start }
      sleep(0.5)
      manager.terminate
    end
  end

  describe '#suspend' do
    it 'suspends the manager' do
      expect(manager.instance_variable_get(:@fetcher)).to receive(:suspend).and_call_original
      task = Async do
        Async { manager.start }
        sleep(0.5)
        manager.suspend
        expect(manager.instance_variable_get(:@done)).to be true
      end
      task.wait
    end
  end

  describe '#terminate' do
    it 'terminates the manager' do
      expect(manager.instance_variable_get(:@fetcher)).to receive(:suspend).and_call_original
      task = Async do
        Async { manager.start }
        sleep(0.5)
        manager.terminate
        sleep(2) # wait for timeout
        expect(manager.instance_variable_get(:@done)).to be true
      end
      task.wait
    end
  end
end
