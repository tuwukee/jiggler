# frozen_string_literal: true

module Jiggler
  module Support
    module Cleaner
      CLEANUP_FLAG = "jiggler:flag:cleanup"

      # When stats are enabled - monitor is going to periodicly cleanup processes with
      # outdated hearbeats from stats hash. Otherwise, poller is going to cleanup 
      # processes with outdated hearbeats from processes hash.
      def prune_outdated_processes_data(processes_key)
        return 0 unless redis(async: false) { |conn| conn.set(CLEANUP_FLAG, "1", update: false, seconds: 60) }
        
        to_prune = []
        redis(async: false) do |conn|
          processes = conn.call("hgetall", processes_key)

          processes.each_slice(2) do |k, v| 
            heartbeat = JSON.parse(v)["heartbeat"].to_f
            if heartbeat < Time.now.to_i - 60.0 || heartbeat <= 0
              to_prune << k
            end
          end

          conn.call("hdel", processes_key, *to_prune) unless to_prune.empty?
        end

        to_prune.size
      end
    end
  end
end
