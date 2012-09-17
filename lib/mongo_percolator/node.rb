require 'active_support/core_ext/string/inflections'

module MongoPercolator
  module Node
    module ClassMethods
      # Operations are a one-to-one mapping
      def operation(klass)
        # Declare the first direction of the association
        belongs_to klass.to_s.underscore

        # We shouldn't ever declare an operation twice.
        class_name = self.to_s.underscore.to_sym
        raise NameError, "name collision" if klass.respond_to? class_name

        # Declare the other direction of the association
        klass.instance_eval do
          one class_name
        end
      end
    end
    
    def self.included(mod)
      mod.extend ClassMethods
    end
  end
end
