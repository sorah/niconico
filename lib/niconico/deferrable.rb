class Niconico
  module Deferrable
    module ClassMethods
      def deferrable(*keys)
        keys.each do |key|
          binding.eval(<<-EOM, __FILE__, __LINE__.succ)
            define_method(:#{key}) do
              get() unless fetched?
              @#{key}
            end
          EOM
        end
        self.deferred_methods.push *keys
      end

      def deferred_methods
        @deferred_methods ||= []
      end
    end

    def self.included(klass)
      klass.extend ClassMethods
    end

    def fetched?; @fetched; end

    def get
      @fetched = true
    end

    private

    def preload_deffered_values(vars={})
      vars.each do |k,v|
        next unless self.class.deferred_methods.include?(k)
        instance_variable_set "@#{k}", v
      end
    end
  end
end
