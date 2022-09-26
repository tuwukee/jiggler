# frozen_string_literal: true

require "redis"
require "json"

@redis = Redis.new


require_relative "./lib/jiggler"
require_relative "./lib/jiggler/job"

class MyJob
  include Jiggler::Job
  job_options queue: "default"

  def perform
    puts "Hello World"
  end
end

MyJob.perform_async

data = redis.blpop(MAIN_LIST)
json_data = JSON.parse(data) 

# puts into redis once again (?)
# client writes into N queues

server = Ractor.new do
  puts "Server starts: #{self.inspect}"
  puts "Server sends: ping"
  loop do
    sleep 1
    ping = "ping #{Time.now}"
    Ractor.yield ping                       # The server doesn't know the receiver and sends to whoever interested
    received = Ractor.receive                 # The server doesn't know the sender and receives from whoever sent
    puts "Server received: #{received}"
  end
end
  
client = Ractor.new(server) do |srv|        # The server is sent inside client, and available as srv
  puts "Client 1 starts: #{self.inspect}"
  received = srv.take                       # The Client takes a message specifically from the server
  puts "Client 1 received from "         "#{srv.inspect}: #{received}"
  puts "Client 1 sends to "         "#{srv.inspect}: pong"
  srv.send 'pong 1'                           # The client sends a message specifically to the server
end

client2 = Ractor.new(server) do |srv|        
  puts "Client 2 starts: #{self.inspect}"
  received = srv.take                       
  puts "Client 2 received from "         "#{srv.inspect}: #{received}"
  puts "Client 2 sends to "         "#{srv.inspect}: pong"
  srv.send 'pong 2'                          
end

client3 = Ractor.new(server) do |srv|        
  puts "Client 3 starts: #{self.inspect}"
  received = srv.take                       
  puts "Client 3 received from "         "#{srv.inspect}: #{received}"
  puts "Client 3 sends to "         "#{srv.inspect}: pong"
  srv.send 'pong 3'                          
end
  
[client, server].each(&:take)               

