# frozen_string_literal: true

module Jiggler
  class RetryHandled < ::RuntimeError; end
  class UnknownJobError < StandardError; end
end
