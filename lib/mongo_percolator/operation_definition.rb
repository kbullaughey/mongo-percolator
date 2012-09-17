module MongoPercolator

  # Abstract operation class from which operations inherit.
  # 
  # Each operation should have an emit function
  class OperationDefinition
    include MongoMapper::Document
    include Addressable
    set_collection_name "operations_graph"

    # These domain-specific langauge methods are to be used in specifying the 
    # operation definition that inherits from this class.
    module DSL
      # Adds a computed property. It takes a block, which should define a property
      # by the same name using any of the standard MongoMapper means, such as key,
      # one, many, etc.
      def computes(property)
        @computed_properties ||= []
        @computed_properties.push property.to_s
        yield
      end

      # Adds a dependency
      # @param path [String] Dot-separated string giving the location of data 
      #   needed for emit()
      def depends_on(path)
        @dependencies ||= Set.new
        @dependencies.add path
      end
    end

    # These class methods are for general use and not really part of the DSL
    module ClassMethods
      # Return the list of properties that are computed by this operation
      def computed_properties
        @computed_properties || []
      end

      def dependencies
        @dependencies || []
      end
    end

    extend DSL    
    extend ClassMethods

    # Collect all the data required to perform the operation. This instance
    # method requires that all the parent associations on which computed 
    # properties depend are set and available on the instance.
    # @return [Hash] data passed to emit
    def gather(root)
      Hash[self.class.dependencies.collect { |dep| [dep, fetch(dep, root)] }]
    end
  end 
end
