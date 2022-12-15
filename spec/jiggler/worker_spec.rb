# frozen_string_literal: true

require_relative "../fixtures/my_job"
require_relative "../fixtures/my_failed_job"

RSpec.describe Jiggler::Worker do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1, 
      timeout: 1, 
      verbose: true,
      queues: ["default", "test"]
    ) 
  end
  let(:collection) { Jiggler::Stats::Collection.new(config) }
  let(:worker) do 
    described_class.new(config, collection) do
      config.logger.debug("Callback called: #{rand(100)}")
    end
  end

  describe "#run" do
    it "runs the worker and performs the job" do
      expect do
        task = Async do
          expect(worker).to receive(:fetch_one).at_least(:once).and_call_original
          expect(worker).to receive(:execute_job).and_call_original
          worker.run
          MyJob.perform_async
          Async do
            sleep 1
            worker.terminate
          end
        end
        task.wait 
      end.to output("Hello World\n").to_stdout
      Jiggler.config.with_redis(async: false) { |conn| conn.del("jiggler:list:default") }
    end

    it "runs the worker and adds the job to retry queue" do
      expect do
        task = Async do
          expect(worker).to receive(:fetch_one).and_call_original
          expect(worker).to receive(:execute_job).and_call_original
          worker.run
          MyFailedJob.perform_async
        end
         task.wait 
      end.to change { 
        Jiggler.config.with_redis(async: false) { |conn| conn.zcard(config.retries_set) }
      }.by(1)
      worker.terminate
      Jiggler.config.with_redis(async: false) { |conn| conn.del("jiggler:list:test") }
      Jiggler.config.with_redis(async: false) { |conn| conn.del("jiggler:set:retries") }
    end
  end

  describe "#terminate" do
    context "when worker is running" do
      it "terminates the worker" do
        task = Async do
          expect(worker.done).to be false
          worker.run
          worker.terminate
        end
        task.wait
        expect(worker.done).to be true
      end
    end

    context "when worker is not running" do
      it do
        expect(worker.done).to be false
        worker.terminate
        expect(worker.done).to be true
      end
    end
  end
end
