# frozen_string_literal: true

module Jiggler
  class Cleaner
    CLEANUP_FLAG = "jiggler:flag:cleanup"
    attr_reader :redis

    def initialize(redis)
      @redis = redis
    end

    def prune_hkey(h, key)
      Sync do
        redis do |conn|
          conn.call("hdel", h, key)
        end
      end
    end

    def unforsed_prune_outdated_processes_data(h, prefix)
      return unless Sync { redis { |conn| conn.set(CLEANUP_FLAG, "1", update: false, seconds: 60) } }

      prune_outdated_processes_data(h, prefix)
    end

    def prune_outdated_processes_data(h, prefix)
      to_prune = []
      Sync do
        redis do |conn|
          processes_hash = Hash[*conn.call("hgetall", h)]
          stats_keys = conn.call("scan", "0", "match", "#{prefix}*").last
          
          processes_hash.each do |k, v|
            process_data = JSON.parse(v)
            if process_data["stats_enabled"] && !stats_keys.include?("#{prefix}#{k}")
              to_prune << k
            end
          end
  
          unless to_prune.empty?
            conn.call("hdel", h, *to_prune)
          end
        end
      end
      to_prune
    end
  end
end
