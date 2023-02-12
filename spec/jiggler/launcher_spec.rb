# frozen_string_literal: true

RSpec.describe Jiggler::Launcher do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1,
      timeout: 1,
      server_mode: true,
      # TODO: test with :at_least_once
      mode: :at_most_once
    )
    end
  let(:launcher) { described_class.new(config) }

  describe '#initialize' do
    it 'sets correct attrs' do
      expect(launcher.config).to eq config
    end
  end

  describe '#start' do
    it 'starts the launcher' do
      task = Async do
        Async do
          expect(launcher.send(:manager)).to receive(:start).and_call_original
          expect(launcher.send(:poller)).to receive(:start).and_call_original
          expect(launcher.send(:monitor)).to receive(:start).and_call_original
          launcher.start
        end
        sleep(1)
        launcher.stop
      end
      task.wait
    end
  end

  describe '#suspend' do
    it 'suspends the launcher' do
      task = Async do
        Async do
          expect(launcher.send(:manager)).to receive(:suspend).and_call_original
          expect(launcher.send(:poller)).to receive(:terminate).and_call_original
          expect(launcher.send(:monitor)).to receive(:terminate).and_call_original
          launcher.start
        end
        sleep(1)
        launcher.suspend
      end
      task.wait
    end
  end

  describe '#stop' do
    it 'stops the launcher' do
      task = Async do
        Async do
          expect(launcher.send(:manager)).to receive(:terminate).and_call_original
          expect(launcher.send(:poller)).to receive(:terminate).and_call_original
          expect(launcher.send(:monitor)).to receive(:terminate).and_call_original
          launcher.start
        end
        sleep(1)
        launcher.stop
      end
      task.wait
    end
  end
end
