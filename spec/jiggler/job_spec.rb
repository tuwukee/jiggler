# frozen_string_literal: true

require_relative "../fixtures/my_job"

RSpec.describe Jiggler::Job do
  let(:job) { MyJob.new(name: "Woo") }

  it "has correct attrs" do
    expect(job.class.queue).to eq "default"
    expect(job.class.retries).to be 1
    expect(job.args).to eq({ name: "Woo" })
    expect(job.name).to eq "MyJob"
    expect(job.send(:list_name)).to eq "jiggler:list:default"
    expect(job.send(:job_args)).to eq({ 
      name: "MyJob", 
      args: { name: "Woo" }, 
      retries: 1 
    }.to_json)
  end

  describe "#perform" do
    it "adds the job to the queue" do
      # expect { job.perform_async.wait }.to change {
      #   Jiggler.redis(async: false) { |conn| conn.llen("jiggler:list:default") } 
      # }.by(1)
      expect(job.perform_async.wait).to be 1
    end
  end
end
