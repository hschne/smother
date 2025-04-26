# frozen_string_literal: true

require_relative "smother/version"
require_relative "smother/proxy"
require_relative "smother/mock"
require_relative "smother/instance"

module Smother
  class << self
    # Der Name ist Programm!
    def my_code(paths: ["."], logger: Logger.new(nil))
      Instance.new(paths, logger).run
    end
  end
end
