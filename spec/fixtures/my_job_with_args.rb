# frozen_string_literal: true

class MyJobWithArgs
  include Jiggler::Job
  job_options retries: 2

  def perform(str, int, float, bool, array, hash)
    if !(str.is_a?(String) &&
      int.is_a?(Integer) &&
      float.is_a?(Float) &&
      bool.is_a?(TrueClass) &&
      array.is_a?(Array) &&
      hash.is_a?(Hash))

      raise StandardError, "Args are not the correct type ◉ ︵ ◉"
    end
  end
end
