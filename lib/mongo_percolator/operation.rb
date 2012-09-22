module MongoPercolator

  # Abstract operation class from which operations inherit.
  # 
  # Each operation should have an emit function
  class Operation
    include MongoMapper::Document
    include Addressable

    key :parent_ids, Array, :typecast => 'BSON::ObjectId'
    key :_old, Boolean, :default => false

    # These domain-specific langauge methods are to be used in specifying the 
    # operation definition that inherits from this class.
    module DSL
      # Provide a block that will do the recomputation. This block will be 
      # executed in the context of the node, and thus have access to member 
      # functions and variables.
      def emit &block
        raise ArgumentError, "Emit block takes no args" unless block.arity == 0
        raise Collision, "emit already called" unless @emit.nil?
        @emit = block
      end

      # Adds a computed property. It takes a block, which should define a property
      # by the same name using any of the standard MongoMapper means, such as key,
      # one, many, etc. The block is executed in the context of the node that the
      # operation part of.
      #
      # A block is not required. For example, if one wants to define the keys in
      # A parent class from which nodes with differing operations descend, this
      # can be done in the parent class and then a block is not needed. However,
      # be sure that the property passed to computes() matches the name of the
      # key or association.
      #
      # @param property [Symbol] Name of computed property
      # @param &body [Block] A block defining the key or association for the 
      #   computed property (optional)
      def computes(property, &body)
        @computed_properties ||= {}
        @computed_properties[property.to_sym] = body
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

      # Return the emit block
      def emit_block
        @emit
      end

      # Indicate whether the property is a computed property.
      #
      # @param property [Symbol] Name of property.
      def computed_property?(property)
        computed_properties.include? property.to_sym
      end

      # This is called when the operation is declared on a node. It performs
      # some additional setup.
      def finalize
        unless @finalized
          raise NotImplementedError, "Need emit" if @emit.nil?
          parents.freeze
          @finalized = true
        end
      end

      # Set up the belongs_to direction of the association. Since each operation 
      # can only belong to one node, we can always use the reader :node so that
      # regardless of the class, we can find the node.
      #
      # @param klass [Class] The class of the node.
      def attach(klass)
        raise Collision, "Operation already attached" if @attached
        @attached = true
        belongs_to :node, :class => klass
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

    # Recompute the computed properties. If the node has not been saved then
    # the node association won't be working. in this case, we can pass in 
    # a node object to use. This is important when the validations required
    # to save the node depend on the computed properties. Without the abilty
    # to pass in the node, we wouldn't be able to compute the properties
    # required to pass the validations becuase we couldn't load the node
    # through the association because it hasn't been saved.
    #
    # @param given_node [MongoPercolator::Node] Node to recompute.
    def recompute(given_node = nil)
      given_node ||= node
      raise KeyError, "node is nil" if given_node.nil?

      # Special variable used inside the block
      gathered_inputs = gather

      # Since I need access to the inputs from inside the emit block, I add
      # a singleton method to get them.
      given_node.define_singleton_method :inputs do
        gathered_inputs
      end

      # Execute the emit block in the context of the node, and save it.
      given_node.instance_eval &emit_block
      nil
    end

    # Same as recompute() but it saves the node at the end
    def recompute!(given_node = nil)
      given_node ||= node
      recompute(given_node)
      given_node.save!
    end

    # Get the emit block from the class variable
    def emit_block
      self.class.emit_block
    end

    # Collect all the data required to perform the operation. This instance
    # method requires that all the parent associations on which computed 
    # properties depend are set and available on the instance.
    #
    # @return [Hash] data passed to emit
    def gather
      Hash[dependencies.collect { |dep| [dep, fetch(dep)] }]
    end

    # Indicate whether the object is a parent of this operation.
    #
    # @return [Boolean]
    def parent?(object)
      parent_ids.include? object.id
    end

    # Instance verion of Operation.computed property
    def computed_property?(property)
      self.class.computed_property? property
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
