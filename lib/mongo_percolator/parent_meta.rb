module MongoPercolator
  class ParentMeta
    include Addressable

    module ClassMethods
      # Serialize the parents hash into {name => count}, parent_ids format.
      def to_mongo(val)
        # If we're not given a ParentMeta, then make one before converting it 
        # to mongo, this way if there are any problems, an exception will be 
        # raised.
        return nil if val.nil?
        val = self.from_mongo(val) unless val.is_a?(self)
        {'ids' => val.ids, 'meta' => val.meta}
      end

      def from_mongo(val)
        return nil if val.nil?
        val.is_a?(self) ? val : ParentMeta.new(val)
      end
    end
    extend ClassMethods

    attr_reader :parents

    # Create a ParentMeta object. The meta data passed to initialize is a hash 
    # of the form {'ids' => [<parent ids>], 'meta' => {:parent_name => count}}
    def initialize(data = {})
      data = {} if data.nil?
      raise TypeError, "Expecting a hash" unless data.kind_of? Hash

      # Store parent names as strings
      data.stringify_keys!
      data['ids'] ||= []
      data['meta'] ||= {}

      raise ArgumentError, "Hash length should be two" unless data.length == 2
      raise TypeError, "Expecting a hash for meta" unless 
        data['meta'].kind_of? Hash

      parent_names = data['meta'].keys.collect{|k| k.to_s}
      raise ArgumentError, "Non-unique keys when stringified" if
        parent_names.length != parent_names.uniq.length
      # Now we can safely stringify
      data['meta'].stringify_keys!

      # Make sure all the counts are numeric, and that we have the right nubmer
      # of ids.
      raise TypeError, "Parent count must be a fixnum" if 
        data['meta'].values.select{|v| !v.is_a?(Fixnum)}.count > 0
      raise ArgumentError, "id list unexpected length" unless 
        data['ids'].length == data['meta'].values.sum

      # Combine the list of parents and their counts with the list of ids to
      # make a hash of parent ids.
      @parents = {}
      data['meta'].keys.sort.each do |parent|
        @parents[parent] = data['ids'].shift data['meta'][parent]
      end

      # Keep track of the parent labels, this will get frozen to prevent more 
      # types being added to operations after instantiation.
      @parent_types = Set.new @parents.keys
    end

    # Generate the flat list of ids given the current state. In order to ensure
    # that we correctly reconstruct the serialized version, we pack the ids
    # in order of sorted parent.
    def ids
      flat_list = []
      @parents.keys.sort.collect do |parent|
       flat_list +=  @parents[parent]
      end
      flat_list
    end

    def meta
      Hash[parents.each.collect {|p,pids| [p, pids.length] }]
    end

    # Get the ids for the given parent
    def [](parent)
      parent = parent.to_s
      raise KeyError unless @parents.include? parent
      @parents[parent]
    end

    # Set the parent's list of ids
    def []=(parent, parent_ids)
      parent = parent.to_s
      raise TypeError, "Parent ids must be array" unless parent_ids.is_a? Array
      @parents[parent] = parent_ids
      @parent_types.add parent unless @parent_types.include? parent
    end

    def length
      @parents.values.collect{|parent_ids| parent_ids.length}.sum
    end

    # Return the name of the i'th parent
    def parent_at(i)
      @parents.keys.sort.collect {|p| [p] * @parents[p].length }.flatten[i]
    end

    # This results in no additional parent types being addable, but the 
    # individual lists of parents can still be modified.
    def freeze
      @parent_types.freeze
    end

    # Determine whether the parent label exists for this parent meta
    #
    # @param parent [String|Symbol] Parent label to check for.
    def include?(parent)
      parent = parent.to_s
      @parents.include? parent
    end
  end
end

# END
