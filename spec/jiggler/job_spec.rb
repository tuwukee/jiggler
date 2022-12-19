# frozen_string_literal: true

require_relative "../fixtures/my_job"

RSpec.describe Jiggler::Job do
  describe ".job_options" do
    context "on default" do
      let(:job) { MyJob.new }

      before do
        MyJob.job_options # reset to default
      end

      it "has correct attrs" do
        expect(job.class.queue).to eq "default"
        expect(job.class.retries).to be 0
        expect(job.class.name).to eq "MyJob"
      end
    end

    context "with custom options" do
      let(:job) { MyJob.new }

      before do
        MyJob.job_options(queue: "custom", retries: 3)
      end

      it "has correct attrs" do
        expect(job.class.queue).to eq "custom"
        expect(job.class.retries).to be 3
        expect(job.class.name).to eq "MyJob"
      end
    end
  end

  describe ".enqueue" do
    it "adds the job to the queue" do
      expect { MyJob.with_options(queue: "mine").enqueue }.to change { 
        Jiggler.config.with_redis(async: false) { |conn| conn.llen("jiggler:list:mine") }
      }.by(1)
      Jiggler.config.with_redis(async: false) { |conn| conn.del("jiggler:list:mine") }
    end

    it "adds the job to the queue asynchonously" do
      expect { MyJob.with_options(queue: "mine", async: true).enqueue.wait }.to change { 
        Jiggler.config.with_redis(async: false) { |conn| conn.llen("jiggler:list:mine") }
      }.by(1)
      Jiggler.config.with_redis(async: false) { |conn| conn.del("jiggler:list:mine") }
    end
  end

  describe ".enqueue_in" do
    it "adds the job to the scheduled set" do
      expect { MyJob.with_options(queue: "mine").enqueue_in(1) }.to change { 
        Jiggler.config.with_redis(async: false) do |conn| 
          conn.call("zcard", Jiggler.config.scheduled_set) 
        end
      }.by(1)
    end
  end
end
