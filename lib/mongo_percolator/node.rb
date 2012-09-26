require 'active_support/core_ext/string/inflections'

module MongoPercolator
  module Node
    include MongoPercolator::Addressable

    module DSL
      # Operations are a one-to-one mapping
      def operation(label, klass)
        raise ArgumentError, "Expecting class" unless klass.kind_of? Class
        raise ArgumentError, "Malformed label" unless 
          label =~ /^[a-z][A-Za-z0-9_?!]*$/

        # Declare the first direction of the association
        one label, :class => klass, :foreign_key => :node_id, 
          :dependent => :destroy

        # Declare the other direction of the association
        klass.attach self

        # Invoke the blocks accompanying computed properties. I execute the
        # block in our own context using instance_eval.
        klass.computed_properties.values.each do |block|
          instance_eval &block unless block.nil?
        end

        klass.finalize
      end

      # Wrapper for declaring many associations, if the association is 
      # many-to-many then some special setup is required.
      #
      # @param label [Symbol] Lable for many association.
      # @param options [Hash] Options for this association.
      # @param extension [Block] Optional block providing extension.
      def many(label, options = {}, &extension)
        super
        label = label.to_sym
        @manys ||= {}
#        @manys[label] = ManyDescription.new 
        binding.pry
      end
    end

    module ClassMethods
      # This will be executed when this module is included in a class, after 
      # MongoMapper::Document is included.
      def setup
        before_save :propagate
        before_save :refresh_many_ids
      end
    end
    
    def self.included(mod)
      # For some reason I can't simply include MongoMapper::Document. I need to
      # defer it until MongoPercolator::Document itself is included because I
      # think MongoMapper::Document assumes that it's getting included into a 
      # class and not another module.
      mod.instance_eval { include MongoMapper::Document }
      mod.extend DSL
      mod.extend ClassMethods
      mod.setup
    end

    #-----------------
    # Instance methods
    #-----------------

    # Check to see if any other nodes depend on this one and if so, cause them 
    # to update. This is usually invoked as a before_save callback. Currently, 
    # it's only when a parent is saved that downstream computed properties will
    # get updated.
    def propagate
      # If not saved, then we can't have anything else that depends on us.
      return true if not persisted?

      MongoPercolator::Operation.where(:parent_ids => id).find_each do |op|
        # If we (the parent) have changed in ways that are meaningful to this
        # operation, then we cause the relevant computed properties to be 
        # recomputed. 
        dependencies = op.relevant_changes_for self
        op._old = true unless dependencies.empty?
        op.save!
      end
      return true
    end

    # In order to track many-to-many relationships, which involve maintaining a
    # list of ids at some arbitrary location in the object, I duplicate this 
    # list in the graph.
    def refresh_many_ids
    end
  end
end
