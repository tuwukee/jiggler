# frozen_string_literal: true

RSpec.describe Jiggler::Web do
  let(:web) { Jiggler::Web.new }

  describe '#time_ago_in_words' do
    it 'returns the correct string for a timestamp' do
      expect(web.time_ago_in_words(Time.now.to_i - 120)).to eq '2 minutes ago'
    end

    it 'returns nil for nil' do
      expect(web.time_ago_in_words(nil)).to be_nil
    end
  end

  describe '#format_memory' do
    it 'returns the correct string for a memory size' do
      expect(web.format_memory(1024)).to eq '1.0 MB'
    end

    it 'returns ? for nil' do
      expect(web.format_memory(nil)).to eq '?'
    end
  end

  describe '#outdated_heartbeat?' do
    it 'returns true if the heartbeat is older than 2 stats intervals' do
      expect(
        web.outdated_heartbeat?(Time.now.to_i - Jiggler.config[:stats_interval] * 2 - 1)
      ).to be true
    end

    it 'returns false if the heartbeat is newer than 2 stats intervals' do
      expect(web.outdated_heartbeat?(Time.now.to_i - Jiggler.config[:stats_interval])).to be false
    end
  end
end
