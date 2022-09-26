# frozen_string_literal: true

require_relative "./job"

class MyJob
  include Jiggler::Job
  job_options queue: "default"

  def perform
    puts "Hello World: #{rand(100)}"
  end
end
