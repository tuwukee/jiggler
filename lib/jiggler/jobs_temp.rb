# frozen_string_literal: true

require_relative "./job"

class MyJob
  include Jiggler::Job
  job_options retries: 1

  def perform
    puts "Hello World: #{rand(100)}"
  end
end
