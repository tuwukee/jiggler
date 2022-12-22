# frozen_string_literal: true

RSpec.describe Jiggler::Worker do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1, 
      timeout: 1, 
      verbose: true,
      queues: ['default', 'test']
    ) 
  end
  let(:collection) { Jiggler::Stats::Collection.new(config) }
  let(:worker) do 
    described_class.new(config, collection) do
      config.logger.debug("Callback called: #{rand(100)}")
    end
  end

  describe '#run' do
    it 'runs the worker and performs the job' do
      task = Async do
        Async do
          expect(worker).to receive(:fetch_one).at_least(:once).and_call_original
          expect(worker).to receive(:execute_job).at_least(:once).and_call_original
          MyJob.enqueue
          worker.run
        end
        sleep(1)
        worker.terminate
      end
      task.wait
    end

    it 'runs the worker and performs the job with args' do
      expect do
        task = Async do
          Async do
            expect(worker).to receive(:fetch_one).at_least(:once).and_call_original
            expect(worker).to receive(:execute_job).at_least(:once).and_call_original
            MyJobWithArgs.enqueue('str', 1, 2.0, true, [1, 2], { a: 1, b: 2 })
            worker.run
          end
          sleep(1)
          worker.terminate
        end
        task.wait 
      end.to_not change { 
        config.with_redis(async: false) { |conn| conn.call('ZCARD', config.retries_set) }
      }
    end

    it 'runs the worker and adds the job to retry queue' do
      expect do
        task = Async do
          Async do
            expect(worker).to receive(:fetch_one).at_least(:once).and_call_original
            expect(worker).to receive(:execute_job).at_least(:once).and_call_original
            MyFailedJob.enqueue
            worker.run
          end
          sleep(1)
          worker.terminate
        end
        task.wait
      end.to change { 
        config.with_redis(async: false) { |conn| conn.call('ZCARD', config.retries_set) }
      }.by(1)
      config.with_redis(async: false) { |conn| conn.call('DEL', 'jiggler:set:retries') }
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
          expect(worker.done).to be false
          Async { worker.run }
          worker.terminate
        end
        task.wait
        expect(worker.done).to be true
      end
    end

    context 'when worker is not running' do
      it do
        expect(worker.done).to be false
        worker.terminate
        expect(worker.done).to be true
      end
    end
  end
end
