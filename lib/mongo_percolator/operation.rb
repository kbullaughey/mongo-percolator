require 'mongo_percolator/parent_meta'

module MongoPercolator

  # Abstract operation class from which operations inherit.
  # 
  # Each operation should have an emit function
  class Operation
    include MongoMapper::Document
    include Addressable

    # This is faster than timestamps! and gives me one-second resolution. All
    # I use it for is sorting.
    key :timeid, BSON::ObjectId
    before_save { self.timeid = BSON::ObjectId.new }

    # I allow there to be callbacks before, after and around the emit block 
    # invocation. Unlike the emit block itself, the callbacks are executed
    # in the context of the operation.
    define_model_callbacks :emit

    # The primary job of each operation instance is to keep track of which
    # particular parent documents the operation depends on. For this purpose
    # I use a custom mongo type, ParentMeta. The parents object is accessed
    # by reader and writer methods that are set up for each parent lable when
    # they are declared. 
    key :parents, ParentMeta
    attr_protected :parents

    # Start the operation out as needing recomputation.
    key :_old, Boolean, :default => true
    key :_error, Boolean, :default => false
    before_save :determine_if_old

    # These domain-specific langauge methods are to be used in specifying the 
    # operation definition that inherits from this class.
    module DSL
      # Provide a block that will do the recomputation. This block will be 
      # executed in the context of the node, and thus have access to member 
      # functions and variables.
      def emit &block
        ensure_is_subclass
        raise ArgumentError.new("Emit block takes no args").add(to_mongo) unless
          block.arity == 0
        raise Collision.new("emit already called").add(to_mongo) unless @emit.nil?
        @emit = block
      end

      # Adds a dependency
      # @param path [String] Dot-separated string giving the location of data 
      #   needed for emit()
      def depends_on(path)
        ensure_is_subclass
        raise ArgumentError, "Path must enter parent(s)" unless path.include? "."
        dependencies.add path
      end

      # Add a parent.
      # @param reader [Symbol] The underscore version of the class name or the 
      #   reader method name if :class => ClassName is given.
      # @param options [Hash] An optional options hash:
      #   :class [Class] - The class of the parent if not inferrable from label.
      def declare_parent(reader, options={})
        ensure_is_subclass
        klass = guess_class(reader, options)

        # These readers and writers are closures, and so they have access
        # to the local scope, which includes the above three variables.

        # Define a reader method
        define_method reader do
          ensure_parents_exists
          ids = parents[reader]
          raise TypeError.new("expecting singular parent").add(to_mongo) if
            ids.length > 1
          return nil if ids.first.nil?
          if instance_variable_defined? ivar(reader)
            cached = instance_variable_get ivar(reader)
            # Use cached copy if the id hasn't changed
            return cached if cached.id == ids.first
          end
          result = klass.send :find, ids.first
          raise MissingData.new("Failed to find parent #{reader}").add(to_mongo) if
            result.nil?
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
      def declare_parents(reader, options={})
        ensure_is_subclass
        klass = guess_class(reader, options)

        # These readers and writers are closures, and so they have access
        # to the local scope, which includes the above three variables.

        # Define a reader method
        define_method reader do
          ensure_parents_exists
          ids = parents[reader]
          return [] if ids == []
          if instance_variable_defined? ivar(reader)
            cached = instance_variable_get ivar(reader)
            # Use cached copy if the ids haven't changed
            return cached if cached.collect{|x| x.id} == ids
          end
          result = klass.send :find, ids
          raise MissingData.new("Failed to find parents").add(to_mongo) if
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

      # Attach this as an external observer of target_class. 
      def observe_creation_of(target_class)
        # Make the target instance accessible in via an association
        attach(target_class)

        # Set up some variables we'll want in our closures
        label = self.to_s.underscore.sub("/", "_")
        observer_class = self

        # In the context of the target class, we define a method that will be
        # called when an instance of that class is created.
        target_class.after_create do
          # All we need to do is create a new instance of the observer 
          # operation and set the node
          observer_class.create!(:node => self)
        end

        # Since we don't have a 'one' association in the other direction with
        # :dependent => :destroy, we add a before_destroy callback here to 
        # delete the observer when the target is destroyed. This only matters if
        # the target is deleted before the observer has time to run, because
        # usually the observer is destroyed automatically after emit.
        target_class.before_destroy do
          target = observer_class.where(:node_id => id).first
          target.destroy unless target.nil?
        end

        # Operations observing creation only fire once and thus don't need to be
        # kept in the database after they run. Therefore, I add an emit callback
        # to delete the observer once its fired. 
        after_emit { destroy }
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
      raise ArgumentError.new("Not a parent").add(to_mongo) unless
        parent? parent
      raise ArgumentError.new("No matching parent").add(to_mongo) if
        parent_label(parent).nil?
      deps = dependencies.select &match_head(parent_label parent)
      parent_diff = parent.diff
      deps.select { |dep| parent_diff.changed? tail(dep) }
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
      raise MissingData.new("Must belong to node").add(to_mongo) unless
        self.respond_to? :node
      given_node ||= node
      raise KeyError.new("node is nil").add(to_mongo) if given_node.nil?

      # Special variable used inside the block
      gathered = gather

      # Since I need access to the inputs from inside the emit block, I add
      # a pair of singleton methods. The signular version expects to find
      # just one item, and the plural version expects to find an array. Each
      # function takes a parameter giving the address.
      given_node.define_singleton_method :inputs do |addr|
        raise ArgumentError.new("Must provide address").add(to_mongo) if addr.nil?
        gathered[addr]
      end
      given_node.define_singleton_method :input do |addr|
        raise ArgumentError.new("Must provide address").add(to_mongo) if addr.nil?
        raise RuntimeError.new("Too many matches").add(to_mongo) if
          gathered[addr].length > 1
        gathered[addr].first
      end

      # Execute the emit block in the context of the node, and save it.
      run_callbacks :emit do
        given_node.instance_eval &emit_block
      end
      return if destroyed?

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
      not_old
      save!

      nil
    end

    def not_old
      self._old = false
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

    # Indicate whether the operation needs recomputing (i.e. a parent has 
    # changed).
    def old?
      # For a new object (not persisted) we don't worry about whether the 
      # composition has changed, because of course it has
      _old or (persisted? and composition_changed?)
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
      raise ArgumentError.new("parent not found").add(to_mongo) if position.nil?
      parents.parent_at(position).to_sym
    end

    # Remove the parent given by parent_id. There's not guarentee that emit will
    # do something useful if a parent is removed, that's left up to the user to
    # determine.
    def remove_parent(parent_id)
      position = parent_ids.index parent_id
      label = parents.parent_at(position)
      parents[label].delete parent_id
    end

    def composition_changed?
      # If we don't know that we've changed, then use a diff. But exclude _old
      # so that _old can be changed and not always causing the new object to
      # look old.
      properties = %w(parents.ids parents.meta node_id)
      local_diff = diff
      properties.select{|prop| local_diff.changed? prop}.length > 0
    end

    # Mark the operation as having an error. This will prevent it from getting
    # continually percolated
    def error!
      self.set :_error => true
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
        # Make sure the object is persisted before we use its id.
        object.save! unless object.persisted?
        # If this object isn't already a parent, mark this operation as old
        self._old = true unless parent? object
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
