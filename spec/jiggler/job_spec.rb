# frozen_string_literal: true

require_relative "../fixtures/my_job"

RSpec.describe Jiggler::Job do
  describe ".job_options" do
    context "on default" do
      let(:job) { MyJob.new }

      before { MyJob.job_options }

      it "has correct attrs" do
        expect(job.class.queue).to eq "default"
        expect(job.class.retries).to be 0
        expect(job.args).to eq({})
        expect(job.name).to eq "MyJob"
        expect(job.send(:list_name)).to eq "jiggler:list:default"
        expect(job.send(:job_args)).to eq({ 
          name: "MyJob", 
          args: {}, 
          retries: 0
        }.to_json)
      end
    end

    context "with custom options" do
      let(:job) { MyJob.new(name: "Woo") }

      before do
        MyJob.job_options(queue: "custom", retries: 3)
      end

      it "has correct attrs" do
        expect(job.class.queue).to eq "custom"
        expect(job.class.retries).to be 3
        expect(job.args).to eq({ name: "Woo" })
        expect(job.name).to eq "MyJob"
        expect(job.send(:list_name)).to eq "jiggler:list:custom"
        expect(job.send(:job_args)).to eq({ 
          name: "MyJob", 
          args: { name: "Woo" }, 
          retries: 3 
        }.to_json)
      end
    end
  end

  describe ".perform_async" do
    let(:job) { MyJob.new }

    before do
      MyJob.job_options(queue: "mine", retries: 0)
    end

    it "adds the job to the queue" do
      expect(job.perform_async.wait).to be 1
      expect { job.perform_async.wait }.to change { 
        Jiggler.config.with_redis(async: false) { |conn| conn.llen("jiggler:list:mine") }
      }.by(1)
      Jiggler.config.with_redis(async: false) { |conn| conn.del("jiggler:list:mine") }
    end
  end
end
