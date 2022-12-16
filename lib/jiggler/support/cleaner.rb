# frozen_string_literal: true

# TODO: rethink this module
module Jiggler
  module Support
    module Cleaner
      CLEANUP_FLAG = "jiggler:flag:cleanup"

      def prune(uuid)
        redis(async: false) do |conn|
          conn.call("hdel", config.processes_hash, uuid)
        end
      end

      # Monitored process with unavailable stats data will be removed from processes hash
      def prune_outdated_processes_data
        return unless redis(async: false) { |conn| conn.set(CLEANUP_FLAG, "1", update: false, seconds: 60) }
        
        to_prune = []
        redis(async: false) do |conn|
          processes_hash = Hash[*conn.call("hgetall", config.processes_hash)]
          stats_keys = conn.call("scan", "0", "match", "#{config.stats_prefix}*").last
          
          processes_hash.each do |k, v|
            process_data = JSON.parse(v)
            if process_data["stats_enabled"] && !stats_keys.include?("#{config.stats_prefix}#{k}")
              to_prune << k
            end
          end

          unless to_prune.empty?
            conn.call("hdel", config.processes_hash, *to_prune)
          end
        end

        logger.debug("Prune outdated processes: #{to_prune.inspect}...")
      rescue => ex
        handle_exception(ex, { context: "Error while pruning outdated processes data" })
      end
    end
  end
end
