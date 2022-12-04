# frozen_string_literal: true

class MyFailedJob
  include Jiggler::Job
  job_options queue: "test", retries: 3

  def perform
    raise StandardError, "Oh no!"
  end
end
