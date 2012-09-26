module MongoPercolator
  # Instances of this class store copies of many-to-many id lists. This copy 
  # is currently only used to track deletions of the associated objects.
  class ManyInstance
    include MongoMapper::Document

    key :ids, Array
    key :node_id, BSON::ObjectId
    key :node_class, String
    key :path, String
  end

  class ManyDescription
    # @param c [Class] The class in which the many association is being added
    #   to. This must be a descendent of either MongoPercolator::Node or
    #   MongoMapper::EmbeddedDocument which is embedded in a 
    #   MongoPercolator::Node.
    # @param path [String] The path from the root document at which to find
    #   the many association's list of ids.
    def initialize(c, path)
      raise TypeError, "Expecting node class" unless 
        @c.ancestors.include? MongoPercolator::Node
      @node_class = c
      @path = path
    end
  end
end
