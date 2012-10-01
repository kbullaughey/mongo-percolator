require 'mongo_percolator/parent_meta'

module MongoPercolator

  # Abstract operation class from which operations inherit.
  # 
  # Each operation should have an emit function
  class Operation
    include MongoMapper::Document
    include Addressable

    # The primary job of each operation instance is to keep track of which
    # particular parent documents the operation depends on. For this purpose
    # I use a custom mongo type, ParentMeta. The parents object is accessed
    # by reader and writer methods that are set up for each parent lable when
    # they are declared. 
    key :parents, ParentMeta
    attr_protected :parents

    # Start the operation out as needing recomputation.
    key :_old, Boolean, :default => true
    before_save :determine_if_old

    # created_at and updated_at
    timestamps!

    # These domain-specific langauge methods are to be used in specifying the 
    # operation definition that inherits from this class.
    module DSL
      # Provide a block that will do the recomputation. This block will be 
      # executed in the context of the node, and thus have access to member 
      # functions and variables.
      def emit &block
        ensure_is_subclass
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
        ensure_is_subclass
        @computed_properties ||= {}
        @computed_properties[property.to_sym] = body
      end

      # Adds a dependency
      # @param path [String] Dot-separated string giving the location of data 
      #   needed for emit()
      def depends_on(path)
        ensure_is_subclass
        dependencies.add path
      end

      # Add a parent.
      # @param reader [Symbol] The underscore version of the class name or the 
      #   reader method name if :class => ClassName is given.
      # @param options [Hash] An optional options hash:
      #   :class [Class] - The class of the parent if not inferrable from label.
      def parent(reader, options={})
        ensure_is_subclass
        klass = guess_class(reader, options)

        # These readers and writers are closures, and so they have access
        # to the local scope, which includes the above three variables.

        # Define a reader method
        define_method reader do
          ensure_parents_exists
          ids = parents[reader]
          raise TypeError, "expecting singular parent" if ids.length > 1
          return nil if ids.first.nil?
          if instance_variable_defined? ivar(reader)
            cached = instance_variable_get ivar(reader)
            # Use cached copy if the id hasn't changed
            return cached if cached.id == ids.first
          end
          result = klass.send :find, ids.first
          raise MissingData, "Failed to find parent" if result.nil?
          # Cache the parent in an instance variable
          instance_variable_set ivar(reader), result
          result
        end

        # Define a reader for the id of the single parent
        define_method "#{reader}_id" do
          ensure_parents_exists
          parents[reader].first
        end
        
        # Define a writer method
        define_method "#{reader}="do |object|
          ensure_parents_exists
          update_ids_using_objects(reader, [object])
        end

        # Define a writer for the id of the single parent
        define_method "#{reader}_id=" do |id|
          ensure_parents_exists
          update_ids(reader, [id])
        end
      end

      # Add a parent. Use this method when there is a variable number of 
      # parents of the given type.
      #
      # @param reader [Symbol] The underscore version of the class name or the 
      #   reader method name if :class => ClassName is given.
      # @param options [Hash] An optional options hash:
      #   :class [Class] - The class of the parent if not inferrable from label.
      #   :no_singularize [Boolean] - Don't singularize when guessing the
      #     class name
      def parents(reader, options={})
        ensure_is_subclass
        klass = guess_class(reader, options)

        # These readers and writers are closures, and so they have access
        # to the local scope, which includes the above three variables.

        # Define a reader method
        define_method reader do
          ensure_parents_exists
          ids = parents[reader]
          if instance_variable_defined? ivar(reader)
            cached = instance_variable_get ivar(reader)
            # Use cached copy if the ids haven't changed
            return cached if cached.collect{|x| x.id} == ids
          end
          result = klass.send :find, ids
          raise MissingData, "Failed to find parents" if
            result.length != ids.length
          # I freeze the resulting array, so that people won't expect to be able
          # to add elements. If individual elements are modified, these need to
          # be individually saved. They will not be saved when the overall
          # operation is saved.
          result.freeze
          # Cache the parent in an instance variable
          instance_variable_set ivar(reader), result
          result
        end

        define_method "#{singular(reader, options)}_ids" do
          ensure_parents_exists
          parents[reader]
        end
        
        # Define a writer method. Writing objects will cause them to be saved.
        define_method "#{reader}="do |objects|
          ensure_parents_exists
          update_ids_using_objects(reader, objects)
        end

        # Define a writer for ids
        define_method "#{singular(reader, options)}_ids=" do |ids|
          ensure_parents_exists
          update_ids(reader, ids)
        end
      end
    end

    # These class methods are for general use and not really part of the DSL
    module ClassMethods
      # @private
      def guess_class(reader, options)
        ensure_is_subclass

        # Keep track of the class of each parent
        klass = options[:class]
        if klass.nil?
          guess = reader.to_s
          guess = guess.singularize unless options[:no_singularize]
          klass = guess.camelize.constantize
        end
        raise ArgumentError, "Expecting Class" unless klass.kind_of? Class

        # I take note of all the parent labels defined
        @parent_labels ||= Set.new
        @parent_labels.add reader

        klass
      end

      # Return the list of properties that are computed by this operation
      def computed_properties
        ensure_is_subclass
        @computed_properties || {}
      end

      # Return the set of dependencies
      def dependencies
        ensure_is_subclass
        @dependencies ||= Set.new
        @dependencies
      end

      # Return the emit block
      def emit_block
        ensure_is_subclass
        @emit
      end

      # Return the array of parent labels
      def parent_labels
        ensure_is_subclass
        @parent_labels
      end

      # Indicate whether the property is a computed property.
      #
      # @param property [Symbol] Name of property.
      def computed_property?(property)
        ensure_is_subclass
        computed_properties.include? property.to_sym
      end

      # This is called when the operation is declared on a node. It performs
      # some additional setup.
      def finalize
        ensure_is_subclass
        unless @finalized == true
          raise NotImplementedError, "Need emit" if @emit.nil?
          @parent_labels.freeze
          @finalized = true
        end
      end

      # Set up the belongs_to direction of the association. Since each operation 
      # can only belong to one node, we can always use the reader :node so that
      # regardless of the class, we can find the node.
      #
      # @param klass [Class] The class of the node.
      def attach(klass)
        ensure_is_subclass
        raise Collision, "Operation already attached" if @attached
        @attached = true
        belongs_to :node, :class => klass
      end

      def ensure_is_subclass
        raise RuntimeError, "Operation must be subclassed" if 
          self == MongoPercolator::Operation
      end

      def singular(label, options)
        options[:no_singularize] ? label : label.to_s.singularize.to_sym
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
      raise MissingData, "Must belong to node" unless self.respond_to? :node
      given_node ||= node
      raise KeyError, "node is nil" if given_node.nil?

      # Special variable used inside the block
      gathered = gather

      # Since I need access to the inputs from inside the emit block, I add
      # a pair of singleton methods. The signular version expects to find
      # just one item, and the plural version expects to find an array. Each
      # function takes a parameter giving the address.
      given_node.define_singleton_method :inputs do |addr|
        raise ArgumentError, "Must provide address" if addr.nil?
        gathered[addr]
      end
      given_node.define_singleton_method :input do |addr|
        raise ArgumentError, "Must provide address" if addr.nil?
        raise RuntimeErorr, "Too many matches" if gathered[addr].length > 1
        gathered[addr].first
      end

      # Execute the emit block in the context of the node, and save it.
      given_node.instance_eval &emit_block

      # When we save an operation, if the composition has changed (i.e. the 
      # identities of the parents) then it will be marked as old. However, if 
      # we recompute, this doesn't matter, the operation should not be old. 
      # However, when we save the operation after recomputation, it will be 
      # marked as old because the composition has changed. An easy, albeit 
      # somewhat inefficient way to get around this is to save the operation 
      # before recomputation if the composition has changed. That way after the 
      # computation, when we mark it as no longer old and save again, the 
      # callback won't mark it as old again. 
      save! if composition_changed?

      # Indicate that we're no longer old and save.
      self._old = false
      save!

      nil
    end

    # Same as recompute() but it saves the node at the end
    def recompute!(given_node = nil)
      raise MissingData, "Must belong to node" unless self.respond_to? :node
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

    # Indicate whether the operation needs recomputing (i.e. a parent has 
    # changed).
    def old?
      _old or composition_changed?
    end

    # Reach into the parent meta and get the parent ids
    def parent_ids
      [] if parents.nil?
      parents.ids
    end

    # The label for a parent class is not necessarily the underscore version of
    # the class name, so we look up the label.
    #
    # @param parent [MongoMapper::Document]
    # @return [Symbol] the label for the parent
    def parent_label(parent)
      position = parent_ids.index parent.id
      raise ArgumentError, "parent not found" if position.nil?
      parents.parent_at(position).to_sym
    end

    def composition_changed?
      # If we don't know that we've changed, then use a diff. But exclude _old
      # so that _old can be changed and not always causing the new object to
      # look old.
      ! diff.diff.reject{|key,val| key == '_old'}.empty?
    end

  private
    def ivar(name)
      "@#{name}".to_sym
    end

    def ensure_parents_exists
      self.parents ||= ParentMeta.new
    end

    def update_ids_using_objects(reader, objects)
      ids = []
      objects.each do |object|
        # If this object is already a parent of this operation, then if the 
        # object has changed, saving it will cause the operation to be marked 
        # as old. If the object is not a parent, then we mark it as old because
        # it has a new parent. And thus saving it first isn't a problem because
        # the operation will be marked as old anyway, here, and we don't need
        # to rely on the the save callback to do so.
        object.save!
        unless parent? object
          self._old = true
        end
        ids.push object.id
      end
      parents[reader] = ids
    end

    def update_ids(reader, ids)
      unless parents.include? reader and parents[reader] == ids
        parents[reader] = ids
        self._old = true
      end
    end

    def determine_if_old
      self._old = true if old?
    end
  end 
end
