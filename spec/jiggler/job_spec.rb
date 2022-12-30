# frozen_string_literal: true

RSpec.describe Jiggler::Job do
  let(:config) do
    Jiggler::Config.new(
      concurrency: 1,
      timeout: 1,
      poller_enabled: false
    )
  end
  describe '.job_options' do
    context 'on default' do
      let(:job) { MyJob.new }

      before do
        MyJob.job_options # reset to default
      end

      it 'has correct attrs' do
        expect(job.class.queue).to eq 'default'
        expect(job.class.retries).to be 0
        expect(job.class.retry_queue).to eq 'default'
        expect(job.class.name).to eq 'MyJob'
      end
    end

    context 'with custom options' do
      let(:job) { MyJob.new }

      before do
        MyJob.job_options(queue: 'custom', retries: 3, retry_queue: 'custom_retry')
      end

      it 'has correct attrs' do
        expect(job.class.queue).to eq 'custom'
        expect(job.class.retries).to be 3
        expect(job.class.retry_queue).to eq 'custom_retry'
        expect(job.class.name).to eq 'MyJob'
      end
    end
  end

  describe '.with_options' do
    it 'allows to override options on job level' do
      expect { MyJob.with_options(queue: 'woo').enqueue }.to change { 
        Jiggler.config.redis_pool.acquire { |conn| conn.call('LLEN', 'jiggler:list:woo') }
      }.by(1)
      Jiggler.config.redis_pool.acquire { |conn| conn.call('DEL', 'jiggler:list:woo') }
    end
  end

  describe '.enqueue' do
    it 'adds the job to the queue' do
      expect { MyJob.with_options(queue: 'mine').enqueue }.to change { 
        Jiggler.config.redis_pool.acquire { |conn| conn.call('LLEN', 'jiggler:list:mine') }
      }.by(1)
      Jiggler.config.redis_pool.acquire { |conn| conn.call('DEL', 'jiggler:list:mine') }
    end
  end

  describe '.enqueue_in' do
    it 'adds the job to the scheduled set' do
      expect { MyJob.with_options(queue: 'mine').enqueue_in(1) }.to change { 
        Jiggler.config.redis_pool.acquire do |conn| 
          conn.call('ZCARD', Jiggler.config.scheduled_set) 
        end
      }.by(1)
    end
  end

  describe '#enqueue_bulk' do
    let(:args_arr) do
      [
        ['1', 1, 1.0, true, [1], { '1' => 1 }],
        ['2', 2, 2.0, true, [2], { '2' => 2 }],
        ['3', 3, 3.0, true, [3], { '3' => 3 }]
      ]
    end

    it 'adds the jobs to the queue' do
      expect { MyJobWithArgs.enqueue_bulk(args_arr) }.to change { 
        Jiggler.config.redis_pool.acquire { |conn| conn.call('LLEN', 'jiggler:list:default') }
      }.by(3)
    end
  end
end
