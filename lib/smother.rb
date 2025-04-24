# frozen_string_literal: true

require_relative "smother/version"

class Smother
  module UltraProxy
    def method_missing(method, *_args)
      UltraMock.new(method.to_s)
    end

    def respond_to_missing?(*_args)
      true
    end

    def to_s
      ""
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

  class Executor
    def self.execute(smother_instance)
      original_methods = UltraProxy
        .instance_methods(false)
        .each_with_object({}) do |method, object|
        object[method] = NilClass.instance_method(method) if NilClass.method_defined?(method)
      end

      NilClass.prepend(UltraProxy)
      smother_instance.run
      UltraMock.instance_methods(false).each do |method|
        NilClass.undef_method(method)
      rescue
        nil
      end

      # Restore original methods if they existed
      original_methods.each do |method_name, method|
        NilClass.define_method(method_name, method)
      end
    end
  end

  class << self
    def run(paths = ["."])
      Rails.application.eager_load!
      Executor.execute(Smother.new(paths))
    end
  end

  def initialize(paths)
    @paths = paths.map { |path| File.expand_path(path) }
  end

  def run
    methods = user_defined_methods
    execute_methods(methods)
    self.print(methods)
    nil
  end

  private

  def user_defined_methods
    result = {}

    ObjectSpace.each_object(Class) do |klass|
      next if klass.name == "Smother"

      next if klass.name.nil?

      instance_methods = klass.public_instance_methods(false).select do |method_name|
        location = klass.instance_method(method_name).source_location
        is_user_defined?(location)
      rescue
        false
      end

      class_methods = klass.singleton_class.public_instance_methods(false).select do |method_name|
        location = klass.method(method_name).source_location
        is_user_defined?(location)
      rescue
        false
      end

      next unless !instance_methods.empty? || !class_methods.empty?

      result[klass.name] = {
        instance_methods: instance_methods,
        class_methods: class_methods
      }
    end

    result
  end

  # Execute all methods, catching exceptions
  def execute_methods(methods)
    methods.each do |class_name, methods_hash|
      begin
        klass = Object.const_get(class_name)
      rescue => e
        puts "Failed to get class #{class_name}: #{e.message}"
        next
      end

      klass.prepend(UltraProxy)

      # Execute class methods
      methods_hash[:class_methods].each do |method_name|
        execute_class_method(klass, method_name)
        puts "  Success: #{class_name}.#{method_name}"
      rescue => e
        puts "  Error executing #{class_name}.#{method_name}: #{e.message}"
      end

      # Try to create an instance for instance methods
      begin
        instance = klass.new

        # Execute instance methods
        methods_hash[:instance_methods].each do |method_name|
          execute_instance_method(instance, method_name)
          puts "  Success: #{class_name}##{method_name}"
        rescue => e
          puts "  Error executing #{class_name}##{method_name}: #{e.message}"
        end
      rescue => e
        puts "  Could not create instance of #{class_name}: #{e.message}"
      end
    end
  end

  # Execute a class method with appropriate arguments
  def execute_class_method(klass, method_name)
    method = klass.method(method_name)
    args, kwargs = generate_method_args(method)

    if kwargs.empty?
      klass.public_send(method_name, *args)
    else
      klass.public_send(method_name, *args, **kwargs)
    end
  end

  # Execute an instance method with appropriate arguments
  def execute_instance_method(instance, method_name)
    method = instance.method(method_name)
    args, kwargs = generate_method_args(method)

    if kwargs.empty?
      instance.public_send(method_name, *args)
    else
      instance.public_send(method_name, *args, **kwargs)
    end
  end

  # Generate appropriate arguments for a method based on its signature
  def generate_method_args(method)
    params = method.parameters
    args = []
    kwargs = {}

    params.each do |param_type, param_name|
      param_name ||= :unnamed

      case param_type
      when :req, :opt
        # Required or optional positional argument
        args << generate_value_for_param(param_name)
      when :keyreq, :key
        # Required or optional keyword argument
        kwargs[param_name.to_sym] = generate_value_for_param(param_name)
      end
      # Ignore :rest, :keyrest, :block parameters
    end

    [args, kwargs]
  end

  # Generate a sensible default value based on the parameter name
  def generate_value_for_param(param_name)
    UltraMock.new(param_name)
  end

  def is_user_defined?(location)
    return false unless location

    @paths.any? { |path| location.first.start_with?(path) }
  end

  def print(methods)
    methods.each do |class_name, methods_hash|
      puts "Class: #{class_name}"
      puts "  Instance methods: #{methods_hash[:instance_methods].join(", ")}"
      puts "  Class methods: #{methods_hash[:class_methods].join(", ")}"
    end
  end
end
