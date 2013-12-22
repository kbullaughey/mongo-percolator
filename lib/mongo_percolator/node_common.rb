module MongoPercolator
  module NodeCommon
    extend ActiveSupport::Concern
    include MongoPercolator::Addressable

    module ClassMethods
      # This setup will be called as the super of setup included by either Node
      # or EmbeddedNode, depending on what's included.
      def common_setup
        after_save :refresh_many_ids
        before_destroy :remove_references_to_me
        after_destroy :remove_many_copies
      end
    end

    # In order to track many-to-many relationships, which involve maintaining a
    # list of ids at some arbitrary location in the object, I duplicate this 
    # list in the graph.
    def refresh_many_ids
      Many.update_many_copy_for(self)
      return true
    end

    # This looks in the percolatory many-to-many association lookup table for
    # this document's id, to see if it needs to be removed from any many-to-many
    # associations.
    def remove_references_to_me
      Many.delete_id id
      return true
    end

    # After the root document is destroyed, there's no need to keep Many::Copy
    # documents that are relative to that root.
    def remove_many_copies
      Many::Copy.collection.remove :root_id => id
      true
    end

    # Return a dot-separated string showing the way from this document to the 
    # child with the given id.
    #
    # @param id [BSON::ObjectId] Id of child you which to find.
    def path_to_embedded_child(id)
      paths = []
      embedded_associations.each do |assoc|
        val = send assoc.name
        next if val.nil?
        assoc_name = assoc.name.to_s
        if val.kind_of? Array
          val.each do |v|
            paths.push "#{assoc_name}[#{id}]" if v.id == id
          end
        else
          paths.push assoc_name if val.id == id
        end
      end
      raise ShouldBeImpossible, "Expecting at most one path" if paths.length > 1
      paths.first
    end

    # Return the root document for this node
    def find_root
      _root_document
    end

    def root?
      _root_document == self
    end
  end
end
