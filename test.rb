require 'polyphony'

# Fiber.class_eval do
#   @kek = nil

#   alias_method :old_transfer, :transfer
#   alias_method :old_resume, :resume
#   def resume
#     puts "resume: #{self.object_id}"
#     old_resume
#   end

#   def transfer
#     puts "transfer to: #{self.object_id}, from: #{Fiber.current.object_id}"
#     @kek = Process.clock_gettime(Process::CLOCK_MONOTONIC)
#     old_transfer
#   end
# end
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
@x = 0
tr = TracePoint.new(:fiber_switch) do
  Fiber.instance_eval { @kek = Process.clock_gettime(Process::CLOCK_MONOTONIC) }
end
tr.enable
def fib(n)
  if n <= 1
    1
  else
    (fib(n-1) + fib(n-2))
  end
end

Thread.new do
  loop do
    sleep(0.05)
    switch = Fiber.instance_variable_get(:@kek)
    next if switch.nil?
    next if Process.clock_gettime(Process::CLOCK_MONOTONIC) - switch < 0.05

    Process.kill('URG', Process.pid)
  end
end

Signal.trap('URG') do
  snooze
end

t2 = spin do
  loop do
    break if @x == 7
    sleep 0.1
    puts "in loop: #{Time.now}"
  end
end

trap 'INT' do
  puts 'interrupted'
  @x = true
  Fiber.schedule_priority_oob_fiber { puts 'bruh what!'}
end

7.times do
  spin do
    puts "in fib loop"
    # sleep 0
    t1 = Time.now
    val = fib(38)
    puts "#{val}: #{Time.now - t1}"
    @x += 1
  end
end

t2.await
puts "all #{Process.clock_gettime(Process::CLOCK_MONOTONIC) - start}"
puts "i'm done"