# frozen_string_literal: true

RSpec.describe Jiggler::Config do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1, 
      environment: "test",
      timeout: 1, 
      verbose: true,
      queues: ["test", "test2"],
      require: "test.rb",
      max_dead_jobs: 100,
      dead_timeout_in_seconds: 100
    ) 
  end

  describe "#initialize" do
    it "sets correct attrs" do
      expect(config[:concurrency]).to be 1
      expect(config[:environment]).to eq "test"
      expect(config[:timeout]).to be 1
      expect(config[:verbose]).to be true
      expect(config[:queues]).to eq ["test", "test2"]
      expect(config[:require]).to eq "test.rb"
      expect(config[:max_dead_jobs]).to be 100
      expect(config[:dead_timeout_in_seconds]).to be 100
    end

    it "generates prefixed queues" do
      expect(config.prefixed_queues).to eq ["jiggler:list:test", "jiggler:list:test2"]
    end

    it "gets redis options" do
      expect(config.redis_options).to eq(concurrency: 1, redis_url: ENV["REDIS_URL"])
    end
  end
end
