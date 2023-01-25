# frozen_string_literal: true

module Jiggler
  class QueueReader
    attr_reader :queue, :priority

    def initialize(queue, priority)
      @queue = queue
      @priority = priority
    end
  end
end

# x, y, z
# brpoplpush('x', 'x_#{process_id}_in_progress', timeout)
# brpoplpush('y', 'y_#{process_id}_in_progress', timeout)
# ...
# keys = scan('*_in_progress')
# process_ids_and_queues = keys.map { |k| k.split('_in_progress')[0].split('_') }
# process_ids = process_ids_and_queues.map(&:second)
# failed_processes = process_ids - existing_process_ids
# failed_processes.each do |process_id|
#   original_queue = process_ids_and_queues.find { |(queue, id)| id == process_id }.first
#   queue = "#{process_id}_in_progress"
#   brpoplpush(queue, original_queue, nil)
# end
