# frozen_string_literal: true

class MyJob
  include Jiggler::Job

  def perform
    sleep(60)
    puts "Hello World"
  end
end
