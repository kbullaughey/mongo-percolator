module MongoPercolator
  module EmbeddedNode
    include MongoPercolator::Addressable

    module DSL
    end

    module ClassMethods
      # This will be executed when this module is included in a class, after 
      # MongoMapper::EmbeddedDocument is included.
      def setup
        before_save :propagate
        after_save :refresh_many_ids
        before_destroy :remove_references_to_me
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
      Many.update_many_copy_for(self)
    end

    # This looks in the percolatory many-to-many association lookup table for
    # this document's id, to see if it needs to be removed from any many-to-many
    # associations.
    def remove_references_to_me
      Many.delete_id id
      true
    end
  end
end
