require 'mongo_percolator/node_common'

module MongoPercolator
  module EmbeddedNode
    extend ActiveSupport::Concern
    include MongoPercolator::NodeCommon

    included do
      # For some reason I can't simply include MongoMapper::EmbeddedDocument. I
      # need to defer it until MongoPercolator::Node itself is included because I
      # think MongoMapper::EmbeddedDocument assumes that it's getting included
      # into a class and not another module.
      instance_eval { include MongoMapper::EmbeddedDocument }
      common_setup
    end

    #-----------------
    # Instance methods
    #-----------------

    # Return the path to this document from its parent document
    #
    # @return [String] Partial path to this document from parent.
    def path_to_self_from_parent
      raise TypeError, "Not embedded" unless self.class.embeddable?
      _parent_document.path_to_embedded_child(id) or
        raise MissingData, "Failed to find path from root"
    end

    # Return the path all the way to the root document
    #
    # @return [String] Path all the way to the root document.
    def path_to_root
      fail_safe_counter = 0
      doc = self
      path = nil
      while !doc.root?
        fail_safe_counter += 1
        path = [doc.path_to_self_from_parent, path].compact.join "."
        doc = doc._parent_document
        raise ShouldBeImpossible, "fail safe" if fail_safe_counter > 100
      end
      path
    end
  end
end
