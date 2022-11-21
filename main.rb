require 'async'
require 'async/io/trap'
require 'logger'

Async do
  done = false
  Async do
    loop do
      break puts 'uff, leaving' if done
      sleep 2
      puts 'uff, living'
    end
  end

  trap = Async::IO::Trap.new(:INT)
  trap.install!

  Async(transient: true) do
    trap.wait
    puts 'uff, done'
    done = true
  end
end