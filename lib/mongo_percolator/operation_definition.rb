module MongoPercolator

  # Abstract operation class from which operations inherit.
  # 
  # Each operation should have an emit function
  class OperationDefinition
    include MongoMapper::Document
    set_collection_name "operations_graph"

    # These domain-specific langauge methods are to be used in specifying the 
    # operation definition that inherits from this class.
    module DSL
      # Adds a 
      def updates(property)
        @updated_properties ||= []
        @updated_properties.push property.to_s
      end
    end

    # These class methods are for general use and not really part of the DSL
    module ClassMethods
      # Return the list of properties that are updated by this operation
      def updated_properties
        @updated_properties || []
      end
    end

    extend DSL    
    extend ClassMethods
  end 
end
