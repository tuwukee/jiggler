# frozen_string_literal: true

require_relative "../fixtures/my_job"

RSpec.describe Jiggler::Summary do
  let(:queues) { ["default", "queue1"] }
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1, 
      timeout: 1, 
      verbose: true, 
      queues: queues,
      poller_enabled: false,
      stats_enabled: false
    )
  end

  describe ".all" do
    let(:subject) { described_class.all(config) }

    it "has correct keys and data types" do
      expect(subject).to be_a Hash
      expect(subject.keys).to eq Jiggler::Summary::KEYS
      expect(subject["retry_jobs_count"]).to be_a Integer
      expect(subject["dead_jobs_count"]).to be_a Integer
      expect(subject["scheduled_jobs_count"]).to be_a Integer
      expect(subject["processed_count"]).to be_a Integer
      expect(subject["failures_count"]).to be_a Integer
      expect(subject["monitor_enabled"]).to be_a(String).or be_a(NilClass)
      expect(subject["processes"]).to be_a Hash
      expect(subject["queues"]).to be_a Hash
    end
    
    # flaky test
    it "gets latest data" do
      task = Async do
        launcher = Jiggler::Launcher.new(config)
        uuid = launcher.instance_variable_get(:@uuid)
        MyJob.enqueue
        
        first_summary = described_class.all(config)
        expect(first_summary["queues"]).to include({
          "default" => 1
        })
        expect(first_summary["processes"].keys).to_not include(uuid)
        
        Async { launcher.start }
        sleep(1)
        second_summary = described_class.all(config)
        launcher.stop

        expect(second_summary["queues"]).to_not include({
          "default" => 1
        })
        expect(second_summary["processes"].keys).to include(uuid)
        expect(second_summary["processes"][uuid]).to include({
          "queues" => queues.join(", "),
          "hostname" => Socket.gethostname,
          "pid" => Process.pid,
          "concurrency" => 1,
          "timeout" => 1,
          "stats_enabled" => false,
          "poller_enabled" => false,
          "current_jobs" => []
        })
      end
      task.wait
    end
  end
end
