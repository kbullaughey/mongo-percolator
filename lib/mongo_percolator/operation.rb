require 'mongo_percolator/parent_meta'

module MongoPercolator

  # Abstract operation class from which operations inherit.
  # 
  # Each operation should have an emit function
  class Operation
    include MongoMapper::Document
    include Addressable
    plugin FindAndModifyPlugin

    extend Forwardable
    # The instane method self_class returns self.class, so I can have instance
    # versions of class emthods.
    def_delegators :self_class, :emit_block, :dependencies

    # This is faster than timestamps! and gives me one-second resolution. All
    # I use it for is sorting.
    key :timeid, BSON::ObjectId
    before_save { self.timeid = tick }

    # Each time the operation is saved, I check to see if the composition
    # has changed. Although I only care about this if it's been persisted and
    # if it's not currently being recomputed. Generally new operations start out
    # in the stale state, so I don't need to do this the first time it's saved
    # and if it's saving at the end of computation, then it shouldn't be stale
    # because it's just been recomputed.
    before_save { expire! if persisted? and composition_changed? }

    # Operations start off nieve until their node is initially saved; but if
    # they're created on an already-persisted node, then we can just
    # mature them immediately.
    after_create { mature! unless !respond_to?(:node) or node.nil? }

    # Whether or not the tracked operation is stale. It starts off stale. The
    # only circumstance this should be switched to true is just after creation
    # while the operation is still held by the creator, or as part of an acquire.
    key :stale, Boolean, :default => true

    # Lower numbers have priority over higher numbers. Think of this as 
    # priority in line. To begin with I use the convention:
    #   0 = executed first
    #   1 = executed second
    #   2 = executed third 
    key :priority, Integer, :default => 1

    # Managed by state machine. This is used to get exclusive control of an operation
    # for processing or mark the operation as in an error state. The transitions
    # are only from the :held state. Because only one thread/process can hold
    # an operation at a time, these transitions don't result in race conditions
    # (i.e., within the time the state is read and posted to the database). 
    key :state, String
    attr_protected :state
    state_machine :state, :initial => :nieve, :action => :post_state do
      state :nieve
      state :available
      state :held
      state :error

      event(:mature) { transition :nieve => :available }
      event(:release) { transition :held => :available }
      event(:choke) { transition :held => :error }
      event(:revive) { transition :error => :available }
      # There are two ways to acquire an operation. One is if it hasn't been 
      # persisted, we can use this transition. Otherwise we need to call 
      # acquire (the class method).
      event(:acquire) do 
        transition [:nieve, :held] => :error, :if => lambda {|op| !op.persisted?}
      end
    end

    # Because I don't write state information upon save(), I need to separatly
    # persist it for upon creation.
    after_create do
      set :state => state, :stale => stale, :timeid => tick
    end

    # The primary job of each operation instance is to keep track of which
    # particular parent documents the operation depends on. For this purpose
    # I use a custom mongo type, ParentMeta. The parents object is accessed
    # by reader and writer methods that are set up for each parent lable when
    # they are declared. 
    key :parents, ParentMeta
    attr_protected :parents

    # I allow there to be callbacks before, after and around the emit block 
    # invocation. Unlike the emit block itself, the callbacks are executed
    # in the context of the operation.
    define_model_callbacks :emit

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
      #   :polymorphic [Boolean] - Whether type polymophism should be allowed.
      def declare_parent(reader, options={})
        ensure_is_subclass
        reader = reader.to_sym if reader.is_a? String
        parent_labels.add reader

        # We allow polymorphism on single parents only. It causes a key to be added
        # to the operation <parent_name>_type, which will store the type
        polymorphic = !!options[:polymorphic] || false

        if polymorphic
          key "#{reader}_type", String
          raise ArgumentError, "class shouldn't be given if polymorphic" unless
            options[:class].nil?
        else
          klass = guess_class(reader, options)
        end

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

          # Look up our class if polymorphic 
          klass = self["#{reader}_type"].constantize if polymorphic

          # Instantiate the object.
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
          self["#{reader}_type"] = object.class.to_s if polymorphic
          update_ids_using_objects(reader, [object])
        end

        # Define a writer for the id of the single parent
        define_method "#{reader}_id=" do |id|
          raise RuntimeError, "Cannot assign by id if polymorphic" if polymorphic
          update_ids(reader, [id])
        end
      end

      # Add a parent. Use this method when there is a variable number of 
      # parents of the given type.
      #
      # @param reader [Symbol|String] The underscore version of the class name or the 
      #   reader method name if :class => ClassName is given.
      # @param options [Hash] An optional options hash:
      #   :class [Class] - The class of the parent if not inferrable from label.
      #   :no_singularize [Boolean] - Don't singularize when guessing the
      #     class name
      def declare_parents(reader, options={})
        ensure_is_subclass
        reader = reader.to_sym if reader.is_a? String
        parent_labels.add reader
        raise ArgumentError, "polymorphic not allowed for plural parents" if
          options[:polymorphic]
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
          update_ids_using_objects(reader, objects)
        end

        # Define a writer for ids
        define_method "#{singular(reader, options)}_ids=" do |ids|
          update_ids(reader, ids)
        end
      end

      # Attach this as an external observer of target_class. 
      # @param target_class [Class|Symbol|String] class to be observed. If a
      #   string or symbol is given, it needs to resolve to the full class
      #   name.
      def observe_creation_of(target_class)
        target_class = target_class.to_s if target_class.is_a? Symbol
        target_class = target_class.camelize.constantize if target_class.is_a? String

        # Make the target instance accessible in via an association
        # attach(target_class)
        attach

        # Set up some variables we'll want in our closures
        label = self.to_s.underscore.sub("/", "_")
        observer_class = self

        # In the context of the target class, we define a method that will be
        # called when an instance of that class is created.
        target_class.after_create do
          # All we need to do is create a new instance of the observer 
          # operation and set the node
          observer_class.create! :node => self
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
      # The proper way to acquire and perform an operation all in one go.
      #
      # @param criteria [Hash] query document for selecting an operation.
      # @param sort [String|Array] sort specification appropriate for mongodb.
      # @return [Boolean] whether or not an operation was found to perform.
      def acquire_and_perform(criteria = {}, sort = nil)
        op = acquire(criteria, sort) or return nil
        op.instance_eval { compute }
        op.priority
      end

      # Perform a particular operation
      #
      # @param id [BSON::ObjectId] id of operation to perform.
      def perform!(id)
        perform_on!(nil, id)
      end

      # Perform a particular operation, but also provide a node. You want to use this
      # when the node has not been persisted yet (perhaps because validations require
      # the operation to be performed.
      #
      # @param node [MongoPercolator::Node] node on which to perform the operation.
      # @param id [BSON::ObjectId] id of operation to perform.
      def perform_on!(node, id)
        criteria = {_id: id}
        # If a node has not been persisted, then its operation will still be nieve
        criteria.merge! state: 'nieve' unless node.persisted?
        op = acquire(criteria) or raise FetchFailed.new("Fetch failed").
          add(_id: id, node: node, criteria: criteria)
        # I use instance eval because compute is private, so that you're not
        # tempted to use it directly and circumvent proper state management.
        op.instance_eval { compute(node) }
      end

      # Fetch an operation to perform. Don't use this function.
      #
      # @private
      # @param criteria [Hash] query document for selecting an operation.
      # @param sort [String|Array] sort specification appropriate for mongodb.
      def acquire(criteria = {}, sort = nil)
        sort ||= [['priority', Mongo::ASCENDING], ['timeid', Mongo::ASCENDING]]
        raise ArgumentError, "Expecting Hash" unless criteria.kind_of? Hash
        criteria[:state] ||= 'available'
        criteria[:stale] ||= true
        op = {:$set => {:state => 'held', :stale => false}}
        find_and_modify :query => criteria, :update => op, :sort => sort,
          :new => true
      end

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

      # Return a list of this operation class's dependencies which depend on
      # parent, and for which the parent has changed since it was last persisted.
      #
      # This class verion, is somewhat awkward, and is meant to be used when one
      # wants to check for relevant changes without instantiating the operation,
      # which is one extra step that slows things down. Generally one will want 
      # to use the instance version of this function.
      #
      # @param label [String] label for parent in operation class
      # @param parent [MongoMapper::Document] 
      # @param options [Hash] The following options are possible:
      #   * :against => [Hash|Node] Optional thing to make a diff against.
      def relevant_changes_for(label, parent, options = {})
        against = options[:against]   # defaults to nil
        unless parent_labels.include?(label)
          raise ArgumentError.new("No matching parent").add(:label => label,
            :parent => parent.to_mongo, :options => options)
        end
        deps = dependencies.select &Addressable.match_head(label)
        parent_diff = parent.diff :against => against
        deps.select { |dep| parent_diff.changed? Addressable.tail(dep) }
      end

      # Return the array of parent labels
      def parent_labels
        ensure_is_subclass
        @parent_labels ||= Set.new
        @parent_labels
      end

      # This is called when the operation is declared on a node. It performs
      # some additional setup.
      def finalize
        ensure_is_subclass
        unless @finalized == true
          raise NotImplementedError, "Need emit" if @emit.nil?
          parent_labels.freeze
          @finalized = true
        end
      end

      # Set up the belongs_to direction of the association. Since each operation 
      # can only belong to one node, we can always use the reader :node so that
      # regardless of the class, we can find the node.
      def attach
        ensure_is_subclass
        belongs_to :node, :polymorphic => true
      end

      def ensure_is_subclass
        if self == MongoPercolator::Operation
          raise RuntimeError, "Operation must be subclassed"
        end
      end

      def singular(label, options)
        options[:no_singularize] ? label : label.to_s.singularize.to_sym
      end

      # The label for a parent class is not necessarily the underscore version of
      # the class name, so we look up the label.
      #
      # @param parent_id [BSON::ObjectId]
      # @param parents [ParentMeta | Hash]
      # @return [Symbol] the label for the parent
      def parent_label(parent_id, parents)
        parents = ParentMeta.from_mongo(parents) if parents.kind_of? Hash
        position = parents.ids.index parent_id
        raise ArgumentError.new("parent not found").add(:parent_id => parent_id, 
          :parents => parents.to_mongo) if position.nil?
        parents.parent_at(position).to_sym
      end


      # This is a hack to prevent overwriting state information that may have changed
      # since the object was read. I need to inject this at such a low level so
      # that I can keep intact the chain of super calls inside MongoMapper. For the
      # MongoPercolator::Operation's collection, I override save so that when an
      # already persisted object is updated, it uses the $set operator rather than
      # overwriting the whole document.
      def collection
        # If the document has been persisted already, change the behavior of save()
        # so that it calls update using the $set operator.
        col = super
        col.define_singleton_method :save do |doc, opts|
          id = doc.delete :_id
          id = doc.delete '_id' if id.nil?
          raise MissingData.new("No id found").add(doc.to_mongo) if id.nil?
          # Exclude our state variables from the properites we persist so that saving
          # will not overwrite our state variables.
          doc = doc.reject{|k,v| %(stale state timeid).include? k}
          update({:_id => id}, {:$set => doc}, :upsert => true, 
            :safe => opts.fetch(:safe, @safe))
          id
        end

        # Return the modified collection
        col
      end
    end

    extend DSL
    extend ClassMethods

    # This only retuns the operations knowledge of itself, not necessarily the
    # latest value in the database.
    def stale?
      stale == true
    end

    # Write our state and increment our timeid, but only if we've been persisted.
    def post_state
      set :state => state, :timeid => tick if persisted?
    end

    # This marks an operation as not stale, but is only possible if the op hasn't
    # been persisted. When operations are inserted for the first time their stale
    # flag is included in the write. 
    def fresh!
      raise StateError.new("already persisted").add(to_mongo) if persisted?
      self.stale = false
    end

    # Mark the operation as stale.
    def expire!
      self.stale = true
      set :stale => stale, :timeid => tick
    end

    # Perform the operation using the currently associated node.
    def perform!
      raise MissingData.new("Must have node").add(to_mongo) unless
        self.respond_to? :node
      perform_on!(node)
    end

    # By routing this method through a class method, I ensure that the operation
    # is pulled off the collection using acquire.
    def perform_on!(given_node)
      # If we've been persisted, we need to go through the acquire process, 
      # becuase other code could have acquired the operation already. If we're 
      # not persisted, we can just call compute directly.
      if persisted?
        # It's possible the operation has changed, and so we save it before 
        # performing because we need to go through acquire, which will use the 
        # persisted operation for computation, which may not have the latest parents.
        save!
        self.class.perform_on!(given_node, id)
      else
        acquire!
        compute(given_node)
      end
    end

    def tick
      BSON::ObjectId.new
    end

    # Collect all the data required to perform the operation. This instance
    # method requires that all the parent associations on which computed 
    # properties depend are set and available on the instance.
    #
    # @return [Hash] data passed to emit
    def gather
      Hash[dependencies.collect { |dep| [dep, fetch(dep)] }]
    end

    # Return a list of this operation class's dependencies which depend on
    # parent, and for which the parent has changed since it was last persisted.
    #
    # @param parent [MongoMapper::Document] 
    # @param options [Hash] The following options are possible:
    #   * :against => [Hash|Node] Optional thing to make a diff against.
    def relevant_changes_for(parent, options = {})
      self_class.relevant_changes_for parent_label(parent), parent, options
    end

    # Indicate whether the object is a parent of this operation.
    #
    # @return [Boolean]
    def parent?(object)
      parent_ids.include? object.id
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
      self_class.parent_label parent.id, parents
    end

    # Remove the parent given by parent_id. There's not guarentee that emit will
    # do something useful if a parent is removed, that's left up to the user to
    # determine.
    def remove_parent(parent_id)
      position = parent_ids.index parent_id
      label = parents.parent_at(position)
      parents[label].delete parent_id
    end

    # Examine structural properties of the operation to see if they've changed.
    def composition_changed?
      properties = %w(parents.ids parents.meta node_id)
      local_diff = diff
      properties.select{|prop| local_diff.changed? prop}.length > 0
    end

    # I set up a method so I can forward to self.class
    def self_class
      self.class
    end

  private
    # Cause the emit block to be executed. If the node has not been saved then
    # the node association won't be working. in this case, we can pass in 
    # a node object to use. This is important when the validations required
    # to save the node depend on the computed properties. Without the abilty
    # to pass in the node, we wouldn't be able to compute the properties
    # required to pass the validations becuase we couldn't load the node
    # through the association because it hasn't been saved.
    #
    # This method is private because the perform class method should always
    # be used. This forces the operation to have been persisted before
    # computation, and it makes sure that it's tracker is property maintained.
    # 
    # Computing an operation doesn't actually change the operation object
    # other than the state information (which is separately persisted) and so
    # we don't need to save it. Thus it's not a worry if concurrently
    # executing code modifies the operation and saves it (because we're not
    # at risk of loosing state information).
    #
    # @param given_node [MongoPercolator::Node] Node to recompute.
    def compute(given_node = nil)
      begin
        # Make sure we've reserved this node for computation
        raise RuntimeError.new("Operation not held").add(to_mongo) unless held?

        # Only use the associated node if given_node is nil. I found this was 
        # important when an operation on the node invokes another operation on 
        # the node. In this case, the first operation would save the node again,
        # overwriting the changes made be the second operation. If both exist,
        # then make sure their ids match. 
        if respond_to?(:node) and !node.nil?
          raise ArgumentError.new("Node doesn't match").add(to_mongo) if 
            !given_node.nil? and node.id != given_node.id
          given_node = node if given_node.nil?
        else
          raise KeyError.new("node is nil").add(to_mongo) if given_node.nil?
        end
  
        # Variable I need accessible to the singleton methods below.
        gathered = gather
        deps = dependencies
  
        # Since I need access to the inputs from inside the emit block, I add
        # a pair of singleton methods. The signular version expects to find
        # just one item, and the plural version expects to find an array. Each
        # function takes a parameter giving the address.
        given_node.define_singleton_method :inputs do |addr|
          raise ArgumentError.new("Must provide address").add(to_mongo) if addr.nil?
          raise ArgumentError.new("Invalid address").
            add(to_mongo.merge(:address => addr)) unless deps.include?(addr)
          gathered[addr]
        end
        given_node.define_singleton_method :input do |addr|
          raise ArgumentError.new("Must provide address").add(to_mongo) if addr.nil?
          raise ArgumentError.new("Invalid address").
            add(to_mongo.merge(:address => addr)) unless deps.include?(addr)
          raise RuntimeError.new("Too many matches").add(to_mongo) if
            gathered[addr].length > 1
          gathered[addr].first
        end

        # I provide access to the node's operation we're emitting from via this
        # singleton method. This is to make sure if we modify the operation,
        # we save the modified copy.
        op_instance = self
        given_node.define_singleton_method :self_op do
          op_instance
        end
  
        # Execute the emit block in the context of the node, and save it.
        run_callbacks(:emit) { given_node.instance_eval &emit_block }
        return if destroyed?
  
        given_node.save!
        save!
        release!
      rescue StandardError => e
        # Mark the operation as in the error state, and re-raise the error
        choke!
        raise e
      end
    end

    def ivar(name)
      "@#{name}".to_sym
    end

    def ensure_parents_exists
      self.parents ||= ParentMeta.new
    end

    def update_ids_using_objects(reader, objects)
      ensure_parents_exists
      ids = []
      objects.each do |object|
        # Make sure the object is persisted before we use its id.
        object.save! unless object.persisted?
        ids.push object.id
      end
      parents[reader] = ids
    end

    def update_ids(reader, ids)
      ensure_parents_exists
      unless parents.include? reader and parents[reader] == ids
        parents[reader] = ids
      end
    end
  end 
end
