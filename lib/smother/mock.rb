module Smother
  class Mock
    def initialize(name = "anonymous")
      @name = name
    end

    def method_missing(m, *_args)
      UltraMock.new(m.to_s)
    end

    def respond_to_missing?(*_args)
      true
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
