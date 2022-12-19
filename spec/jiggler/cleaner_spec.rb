# frozen_string_literal: true

RSpec.describe Jiggler::Cleaner do
  let(:config) { Jiggler::Config.new(concurrency: 1, timeout: 1, verbose: true) }
  let(:cleaner) { described_class.new(config) }

  describe "#prune_failures_counter" do
    it "prunes the failures counter" do
      expect(config.redis).to receive(:call).
        with("del", Jiggler::Stats::Monitor::FAILURES_COUNTER)
      cleaner.prune_failures_counter
    end
  end

  describe "#prune_processed_counter" do
    it "prunes the processed counter" do
      expect(config.redis).to receive(:call).
        with("del", Jiggler::Stats::Monitor::PROCESSED_COUNTER)
      cleaner.prune_processed_counter
    end
  end

  describe "#prune_all_processes" do
    it "prunes all processes" do
      expect(config.redis).to receive(:call).with("del", config.processes_hash)
      cleaner.prune_all_processes
    end
  end

  describe "#prune_process" do
    it "prunes a process by its uuid" do
      expect(config.redis).to receive(:call).with("hdel", config.processes_hash, "uuid")
      cleaner.prune_process("uuid")
    end
  end

  describe "#prune_dead_set" do
    it "prunes the dead set" do
      expect(config.redis).to receive(:call).with("del", config.dead_set)
      cleaner.prune_dead_set
    end
  end

  describe "#prune_retries_set" do
    it "prunes the retries set" do
      expect(config.redis).to receive(:call).with("del", config.retries_set)
      cleaner.prune_retries_set
    end
  end

  describe "#prune_scheduled_set" do
    it "prunes the scheduled set" do
      expect(config.redis).to receive(:call).with("del", config.scheduled_set)
      cleaner.prune_scheduled_set
    end
  end

  describe "#prune_all_queues" do
    let(:queues) { ["queue1", "queue2"] }

    it "prunes all queues" do
      allow(config.redis).to receive(:call).
        with("scan", "0", "match", "#{config.queue_prefix}*").
        and_return(["0", queues])
      expect(config.redis).to receive(:call).with("del", *queues)
      cleaner.prune_all_queues
    end
  end

  describe "#prune_queue" do
    it "prunes a queue by its name" do
      expect(config.redis).to receive(:call).with("del", "#{config.queue_prefix}queue")
      cleaner.prune_queue("queue")
    end
  end

  describe "#prune_outdated_processes_data" do
    let(:processes_data) do
      [
        "uuid1", { "stats_enabled" => true }.to_json,
        "uuid2", { "stats_enabled" => false }.to_json,
        "uuid3", { "stats_enabled" => true }.to_json
      ]
    end
    let(:stats_keys) { ["#{config.stats_prefix}uuid3"] }

    it "prunes processes data without uptodate stats" do
      allow(config.redis).to receive(:call).
        with("hgetall", config.processes_hash).
        and_return(processes_data)
      allow(config.redis).to receive(:call).
        with("scan", "0", "match", "#{config.stats_prefix}*").
        and_return(["0", stats_keys])
      expect(config.redis).to receive(:call).with("hdel", config.processes_hash, "uuid1")
      expect(cleaner.prune_outdated_processes_data).to eq(["uuid1"])
    end
  end

  describe "#unforsed_prune_outdated_processes_data" do
    it "sets cleaner flag to prevent multiple prunes from concurrent processes" do
      expect(config.redis).to receive(:call).
        with("SET", Jiggler::Cleaner::CLEANUP_FLAG, "1", "EX", 60, "NX")
      cleaner.unforsed_prune_outdated_processes_data
    end
  end

  describe "#prune_all" do
    it "prunes all data" do
      expect(config.redis).to receive(:pipeline)
      expect(config.redis).to receive(:call).
        with("scan", "0", "match", "#{config.queue_prefix}*").and_return(["0", []])
      cleaner.prune_all
    end
  end
end
