# frozen_string_literal: true

class MyJob
  include Jiggler::Job

  def perform
    puts 'Hello World'
  end
end
