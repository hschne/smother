# frozen_string_literal: true

module Smother
  module Proxy
    def method_missing(method, *_args)
      Smother::Mock.new(method.to_s)
    end

    def respond_to_missing?(*_args)
      true
    end

    def to_s
      to_str
    end

    def to_str
      ""
    end

    def to_hash
      {}
    end

    def to_ary
      []
    end
  end
end
