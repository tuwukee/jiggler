# frozen_string_literal: true

RSpec.describe Jiggler::Worker do
  before(:all) do
    Jiggler.instance_variable_set(:@config, Jiggler::Config.new(
      concurrency: 1,
      client_concurrency: 1,
      timeout: 1,
      queues: [['default', 2], ['test', 1]],
      mode: :at_most_once
    ))
  end
  after(:all) do
    Jiggler.instance_variable_set(:@config, Jiggler::Config.new)
  end

  let(:config) { Jiggler.config }
  let(:uuid) { "#{SecureRandom.hex(3)}-test" }
  let(:collection) { Jiggler::Stats::Collection.new(uuid, uuid) }
  let(:acknowledger) { Jiggler::AtMostOnce::Acknowledger.new(config) }
  let(:fetcher) { Jiggler::AtMostOnce::Fetcher.new(config, collection) }
  let(:worker) do 
    described_class.new(config, collection, acknowledger, fetcher) do
      config.logger.debug("Callback called: #{rand(100)}")
    end
  end

  describe '#run' do
    it 'runs the worker and performs the job' do
      MyJob.enqueue
      task = Async do
        Async do
          expect(worker).to receive(:fetch_one).at_least(:once).and_call_original
          expect(worker).to receive(:execute_job).at_least(:once).and_call_original
          worker.run
        end
        sleep(1)
        worker.terminate
      end
      task.wait
    end

    it 'runs the worker and performs the job with args' do
      expect do
        MyJobWithArgs.enqueue('str', 1, 2.0, true, [1, 2], { a: 1, b: 2 })
        task = Async do
          Async do
            expect(worker).to receive(:fetch_one).at_least(:once).and_call_original
            expect(worker).to receive(:execute_job).at_least(:once).and_call_original
            worker.run
          end
          sleep(1)
          worker.terminate
        end
        task.wait 
      end.to_not change { 
        config.with_sync_redis { |conn| conn.call('ZCARD', config.retries_set) }
      }
    end

    it 'runs the worker and adds the job to retry queue' do
      expect do
        MyFailedJob.enqueue
        task = Async do
          Async do
            expect(worker).to receive(:fetch_one).at_least(:once).and_call_original
            expect(worker).to receive(:execute_job).at_least(:once).and_call_original
            worker.run
          end
          sleep(1)
          worker.terminate
        end
        task.wait
      end.to change { 
        config.with_sync_redis { |conn| conn.call('ZCARD', config.retries_set) }
      }.by(1)
      config.with_sync_redis { |conn| conn.call('DEL', 'jiggler:set:retries') }
    end
  end

  describe '#execute_job' do
    it 'executes the job' do
      expect do
        worker.instance_variable_set(
          :@current_job, 
          Jiggler::Worker::CurrentJob.new(queue: 'default', args: '{ "name": "MyJob", "jid": "321" }')
        )
        worker.send(:execute_job)
      end.to output("Hello World\n").to_stdout
    end
  end

  describe '#terminate' do
    context 'when worker is running' do
      it 'terminates the worker' do
        task = Async do
          Async { worker.run }
          sleep(0.5)
          worker.terminate
        end
        task.wait
        expect(worker.instance_variable_get(:@runner)).to be_nil
      end
    end
  end
end
