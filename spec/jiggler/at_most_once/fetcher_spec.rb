# frozen_string_literal: true

RSpec.describe Jiggler::AtMostOnce::Fetcher do
  describe '#fetch' do
    let(:config) do
      Jiggler::Config.new(
        concurrency: 1,
        timeout: 1,
        poller_enabled: false,
        queues: ['fetcher_queue'],
        mode: :at_most_once
      )
    end
    let(:uuid) { "#{SecureRandom.hex(3)}-test" }
    let(:collection) { Jiggler::Stats::Collection.new(uuid, uuid) }
    let(:fetcher) { Jiggler::AtMostOnce::Fetcher.new(config, collection) }

    after { config.cleaner.prune_all }

    it 'fetches current job' do
      MyJob.with_options(queue: 'fetcher_queue').enqueue

      job = Sync { fetcher.fetch }
      args = Oj.load(job.args)

      expect(job.queue).to eq('jiggler:list:fetcher_queue')
      expect(args['name']).to eq('MyJob')
      expect(args['jid']).to be_a(String)
      expect(args['retries']).to be 0
      expect(args['args']).to eq([])
    end
  end
end
