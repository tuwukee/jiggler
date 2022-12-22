# frozen_string_literal: true

RSpec.describe Jiggler::Launcher do
  let(:config) { Jiggler::Config.new(concurrency: 1, timeout: 1, verbose: true) }
  let(:launcher) { described_class.new(config) }

  describe '#initialize' do
    it 'sets correct attrs' do
      expect(launcher.config).to eq config
      expect(JSON.parse(launcher.process_data).transform_keys(&:to_sym)).to include({
        pid: Process.pid,
        hostname: Socket.gethostname,
        concurrency: 1,
        timeout: 1,
        queues: 'default',
        stats_enabled: true,
        poller_enabled: true
      })
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

  describe '#quite' do
    it 'quites the launcher' do
      task = Async do
        Async do
          expect(launcher.send(:manager)).to receive(:quite).and_call_original
          expect(launcher.send(:poller)).to receive(:terminate).and_call_original
          expect(launcher.send(:monitor)).to receive(:terminate).and_call_original
          launcher.start
        end
        sleep(1)
        launcher.quite
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
