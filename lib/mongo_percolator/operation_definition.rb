module MongoPercolator

  # Abstract operation class from which operations inherit.
  # 
  # Each operation should have an emit function
  class OperationDefinition
    include MongoMapper::Document
    include Addressable

    key :parent_ids, Array, :typecast => 'BSON::ObjectId'

    # These domain-specific langauge methods are to be used in specifying the 
    # operation definition that inherits from this class.
    module DSL
      # Adds a computed property. It takes a block, which should define a property
      # by the same name using any of the standard MongoMapper means, such as key,
      # one, many, etc. The block is executed in the context of the node that the
      # operation part of.
      def computes(property, &body)
        @computed_properties ||= {}
        @computed_properties[property] = body
      end

      # Adds a dependency
      # @param path [String] Dot-separated string giving the location of data 
      #   needed for emit()
      def depends_on(path)
        dependencies.add path
      end

      # Add a parent.
      # @param reader [Symbol] The underscore version of the class name or the 
      #   reader method name if :class => ClassName is given.
      # @param options [Hash] An optional options hash:
      #   :class [Class] - The class of the parent if not inferrable from label.
      #   :position [Integer] - Position in parent_ids array if not given in 
      #     the same order in the class definition as in the array.
      def parent(reader, options={})
        reader = reader.to_sym unless reader.kind_of? Symbol
        writer = "#{reader}=".to_sym

        # Keep track of the class of each parent
        klass = options[:class] || reader.to_s.camelize.constantize
        raise ArgumentError, "Expecting Class" unless klass.kind_of? Class

        # Keep track of how many parents we've defined so we know where in the
        # parent_ids array to look for this one.
        position = options[:position] || parent_count

        # I need to be able to look up the parent association label by position.
        parents[position] = reader

        # These readers and writers are closures, and so they have access
        # to the local scope, which includes information about the class
        # and index of each parent. None of this is persisted to the database
        # and thus depends on the ruby code.

        # Define a reader method
        define_method reader do
          # Cache the parent in an instance variable
          unless instance_variable_defined? ivar(reader)
            parent = klass.send :find, parent_ids[position]
            raise MissingData, "Failed to find parent" if parent.nil?
            instance_variable_set ivar(reader), parent
          end
          instance_variable_get ivar(reader)
        end
        
        # Define a writer method
        define_method writer do |obj|
          # Make sure the object is persisted, because we need the id
          obj.save! unless obj.persisted?
          raise ArgumentError, "No ObjectId" if obj.id.nil?
          parent_ids[position] = obj.id
        end
      end
    end

    # These class methods are for general use and not really part of the DSL
    module ClassMethods
      # Return the list of properties that are computed by this operation
      def computed_properties
        @computed_properties || {}
      end

      # Return the set of dependencies
      def dependencies
        @dependencies ||= Set.new
        @dependencies
      end

      # Give the number of parents defined for this operation
      def parent_count
        parents.length
      end

      # Return the parents hash mapping classes to labels.
      def parents
        @parents ||= []
        @parents
      end

      # This is called when the operation is declared on a node. It performs
      # some additional setup.
      def finalize
        unless @finalized
          parents.freeze
          @finalized = true
        end
      end

      # Set up the forward direction of the association
      def attach(class_name)
        raise Collision, "OperationDefinition already attached" if @attached
        @attached = true
        one class_name
      end
    end

    extend DSL
    extend ClassMethods

    # Return a list of this operation's dependencies which depend on parent,
    # and for which the parent has changed since it was last persisted.
    #
    # @param parent [MongoMapper::Document] 
    def relevant_changes_for(parent)
      raise ArgumentError, "Not a parent" unless parent? parent
      raise ArgumentError, "No matching parent" if parent_label(parent).nil?
      deps = dependencies.select &match_head(parent_label parent)
      deps.select { |dep| parent.diff.changed? tail(dep) }
    end

    # Provide a instance method to return the class's dependencies.
    def dependencies
      self.class.dependencies
    end

    # If the parent has changed in ways that are meaningful to this operation,
    # then we cause the relevant computed properties to be recomputed. This 
    # function is called when the parent is saved. Currently, it's only when
    # a parent is saved that downstream computed properties will get updated.
    #
    # @param parent [Object] Parent instance that has changed. 
    def propagate(parent)
      # Get the subset of dependencies that correspond to this parent label.
      deps_to_recompute = relevant_changes_for parent

      # TODO: Determine if anything along the paths has changed. If so, propagate the update.
    end

    # Collect all the data required to perform the operation. This instance
    # method requires that all the parent associations on which computed 
    # properties depend are set and available on the instance.
    # @return [Hash] data passed to emit
    def gather(root)
      Hash[dependencies.collect { |dep| [dep, fetch(dep, :target => root)] }]
    end

    # Indicate whether the object is a parent of this operation.
    def parent?(object)
      parent_ids.include? object.id
    end
  private
    def ivar(name)
      "@#{name}".to_sym
    end

    # The label for a parent class is not necessarily the underscore version of
    # the class name, so we look up the label.
    #
    # @param parent [MongoMapper::Document]
    # @return [Symbol] the label for the parent
    def parent_label(parent)
      position = parent_ids.index parent.id
      raise ArgumentError, "parent not found" if position.nil?
      self.class.parents[position]
    end
  end 
end
