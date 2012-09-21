require 'active_support/core_ext/string/inflections'

module MongoPercolator
  module Node
    include MongoPercolator::Addressable

    module ClassMethods
      # Operations are a one-to-one mapping
      def operation(klass)
        # Declare the first direction of the association
        belongs_to klass.to_s.underscore.to_sym

        # Declare the other direction of the association
        klass.attach self

        # Invoke the blocks accompanying computed properties. I execute the
        # block in our own context using instance_eval.
        klass.computed_properties.values.each { |block| instance_eval &block }

        klass.finalize
      end

      # This will be executed when this module is included in a class, after 
      # MongoMapper::Document is included.
      def setup
        before_save :propagate
      end
    end
    
    def self.included(mod)
      # For some reason I can't simply include MongoMapper::Document. I need to
      # defer it until MongoPercolator::Document itself is included because I
      # think MongoMapper::Document assumes that it's getting included into a 
      # class and not another module.
      mod.instance_eval { include MongoMapper::Document }
      mod.extend ClassMethods
      mod.setup
    end

    #-----------------
    # Instance methods
    #-----------------

    # Check to see if any other nodes depend on this one and if so, cause them 
    # to update. This is usually invoked as a before_save callback.
    def propagate
      # If not saved, then we can't have anything else that depends on us.
      return true if not persisted?

      MongoPercolator::Operation.where(:parent_ids => id).find_each do |parent|
      end
    end
  end
end
