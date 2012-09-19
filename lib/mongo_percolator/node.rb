require 'active_support/core_ext/string/inflections'

module MongoPercolator
  module Node
    module ClassMethods
      # Operations are a one-to-one mapping
      def operation(klass)
        # Declare the first direction of the association
        belongs_to klass.to_s.underscore.to_sym

        # Declare the other direction of the association
        class_name = self.to_s.underscore.to_sym
        klass.attach class_name

        # Invoke the blocks accompanying computed properties. I execute the
        # block in our own context using instance_eval.
        klass.computed_properties.values.each { |block| instance_eval &block }
      end
    end
    
    def self.included(mod)
      mod.extend ClassMethods
    end
  end
end
