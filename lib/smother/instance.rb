# frozen_string_literal: true

module Smother
  class Instance
    def initialize(paths, logger)
      @paths = paths.map { |path| File.expand_path(path) }
      @logger = logger
    end

    def run
      @user_defined_methods = user_defined_methods
      execute_with_nil_overwrite
      self
    end

    def and_print
      print(@user_defined_methods)
      self
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

    def execute_with_nil_overwrite
      # Executing methods randomly causes so many pesky nil errors. Let's fix that.
      original_methods = Proxy
        .instance_methods(false)
        .each_with_object({}) do |method, object|
        object[method] = NilClass.instance_method(method) if NilClass.method_defined?(method)
      end

      NilClass.prepend(Proxy)
      execute
      Proxy.instance_methods(false).each do |method|
        NilClass.undef_method(method)
      rescue
        nil
      end

      original_methods.each do |method_name, method|
        NilClass.define_method(method_name, method)
      end
    end

    def execute
      @user_defined_methods.each do |class_name, methods_hash|
        begin
          klass = Object.const_get(class_name)
        rescue => e
          @logger.debug("[Smother] Failed to load class #{class_name}: #{e.message}")
          next
        end

        klass.prepend(Proxy)

        methods_hash[:class_methods].each do |method_name|
          execute_class_method(klass, method_name)
          @logger.debug("[Smother] Successfully executed class method #{class_name}.#{method_name}")
        rescue => e
          @logger.debug("[Smother] Error executing class method #{class_name}.#{method_name}: #{e.message}")
        end

        begin
          instance = klass.new

          methods_hash[:instance_methods].each do |method_name|
            execute_instance_method(instance, method_name)
            @logger.debug("[Smother] Successfully executed instance method #{class_name}##{method_name}")
          rescue => e
            @logger.debug("[Smother] Error executing instance method #{class_name}##{method_name}: #{e.message}")
          end
        rescue => e
          @logger.debug("[Smother] Could not instantiate #{class_name}: #{e.message}")
        end
      end
    end

    def execute_class_method(klass, method_name)
      method = klass.method(method_name)
      args, kwargs = generate_method_args(method)

      if kwargs.empty?
        klass.public_send(method_name, *args)
      else
        klass.public_send(method_name, *args, **kwargs)
      end
    end

    def execute_instance_method(instance, method_name)
      method = instance.method(method_name)
      args, kwargs = generate_method_args(method)

      if kwargs.empty?
        instance.public_send(method_name, *args)
      else
        instance.public_send(method_name, *args, **kwargs)
      end
    end

    def generate_method_args(method)
      params = method.parameters
      args = []
      kwargs = {}

      params.each do |param_type, param_name|
        param_name ||= :unnamed

        case param_type
        when :req, :opt
          args << generate_value_for_param(param_name)
        when :keyreq, :key
          kwargs[param_name.to_sym] = generate_value_for_param(param_name)
        end
      end

      [args, kwargs]
    end

    def generate_value_for_param(param_name)
      Smother::Mock.new(param_name)
    end

    def is_user_defined?(location)
      return false unless location

      @paths.any? { |path| location.first.start_with?(path) }
    end

    def print(methods)
      methods.each do |class_name, methods_hash|
        @logger.info("[Smother] Found class: #{class_name}")
        @logger.info("[Smother]   Instance methods: #{methods_hash[:instance_methods].join(", ")}")
        @logger.info("[Smother]   Class methods: #{methods_hash[:class_methods].join(", ")}")
      end
    end
  end
end
