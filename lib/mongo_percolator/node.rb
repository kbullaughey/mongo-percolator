require 'mongo_percolator/node_common'

module MongoPercolator
  module Node
    extend ActiveSupport::Concern
    include MongoPercolator::NodeCommon

    module DSL
      # Operations are a one-to-one mapping
      def operation(label, klass=nil)
        klass = self.const_get(label.to_s.camelize.to_sym) if klass.nil?
        raise ArgumentError, "Expecting class" unless klass.kind_of? Class
        raise ArgumentError, "Malformed label" unless 
          label =~ /^[a-z][A-Za-z0-9_?!]*$/

        # Declare the first direction of the association
        one label, :class => klass, :foreign_key => :node_id, 
          :dependent => :destroy

        # Declare the other direction of the association
        klass.attach self

        # Define a convenience method to create the operation
        define_method "create_#{label}" do |*args|
          arg_hash = args.first || {}
          op = klass.new arg_hash
          raise RuntimeError, "Node should have id" if id.nil?
          op.node_id = id
          op.save!
        end

        klass.finalize
      end
    end

    module ClassMethods
      # This will be executed when this module is included in a class, after 
      # MongoMapper::Document is included.
      def setup
        before_save :propagate
        after_destroy :propagate_destroy
      end
    end
    
    included do
      # For some reason I can't simply include MongoMapper::Document. I need to
      # defer it until MongoPercolator::Node itself is included because I
      # think MongoMapper::Document assumes that it's getting included into a 
      # class and not another module.
      instance_eval { include MongoMapper::Document }
      extend DSL
      common_setup
      setup
    end

    #-----------------
    # Instance methods
    #-----------------

    # Check to see if any other nodes depend on this one and if so, cause them 
    # to update. This is usually invoked as a before_save callback. Currently, 
    # it's only when a parent is saved that downstream nodes will get updated.
    def propagate
      # If not saved, then we can't have anything else that depends on us.
      return true if not persisted?

      MongoPercolator::Operation.where('parents.ids' => id).find_each do |op|
        # If we (the parent) have changed in ways that are meaningful to this
        # operation, then we cause the relevant computed properties to be 
        # recomputed. 
        op._old = true unless op.relevant_changes_for(self).empty?
        op.save!
      end
      return true
    end

    def propagate_destroy
      # Handle the case in which this node is getting destroyed
      return unless destroyed?

      MongoPercolator::Operation.where('parents.ids' => id).find_each do |op|
        op.remove_parent id
        op._old = true
        op.save!
      end
      return true
    end
  end
end
