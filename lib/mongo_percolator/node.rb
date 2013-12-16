require 'mongo_percolator/node_common'

module MongoPercolator
  module Node
    extend ActiveSupport::Concern
    include MongoPercolator::NodeCommon

    extend Forwardable
    def_delegators :self_class, :obey_exports?, :exports

    module DSL
      # Operations are a one-to-one mapping
      def operation(label, klass=nil)
        klass = self.const_get(label.to_s.camelize.to_sym) if klass.nil?
        raise ArgumentError, "Expecting class" unless klass.kind_of? Class
        raise ArgumentError, "Malformed label" unless 
          label =~ /^[a-z][A-Za-z0-9_?!]*$/

        # Declare the first direction of the association
        one label, :class => klass, :as => :node, :dependent => :destroy
        @operations ||= []
        @operations.push label

        # Declare the other direction of the association
        klass.attach
        klass.finalize
      end

      # Export an address so that descendants can depend on it if this node is
      # a parent. Exports are optional. If no exports are defined, then any 
      # time the node is saved, all dependencies of all descendant operations 
      # will be checked for differences using a diff object. If one or more 
      # exports are defined, then only these paths will be eligible for 
      # descendents to depend on. In this case, the exported paths can be checked
      # before propagation so that when the document is saved, propagation will
      # only happen if one of the exported paths is changed according to the 
      # diff. All other paths will appear hidden. 
      #
      # At present, descendants can still access properties that are not exported.
      # The point of exports is to specify a list of paths to monitor for changes
      # that should result in propagation. In the future maybe I'll change this and
      # actually hide all non-exported addresses. 
      #
      # @param addr [String] Path to export and make available for descendents
      def export(addr)
        raise DeclarationError, "Expecting string address" unless 
          addr.kind_of? String
        @exports ||= Set.new
        raise DeclarationError, "Already declared no_exports" if @exports.frozen?
        @exports.add(addr)
      end

      def no_exports
        raise DeclarationError, "Exports already defined" unless @exports.nil?
        @exports = Set.new
        @exports.freeze
      end
    end

    module ClassMethodsLate
      # This will be executed when this module is included in a class, after 
      # MongoMapper::Document is included.
      def setup
        extend ActiveSupport::Callbacks
        # I cause propagation with a before_save handler. However, this creates a
        # problem becuase subsequent before_save handlers will execute after
        # propagation. For this reason, I create another set of callbacks for
        # before, after, and around propagation.
        define_model_callbacks :propagation

        plugin FindAndModifyPlugin
        before_save :propagate
        after_destroy :propagate_destroy
        after_create :release_operations
      end

      # This is a hack to fix find when given multiple ids, it seems that
      # sometimes if there are duplicates, only unique objects are returned.
      def find(*args)
        res = super
        # The fix is only needed if given an array of ObjectIds.
        if args.length == 1 and args.first.is_a? Array
          res_hash = Hash[res.collect{|doc| [doc.id, doc]}]
          res = args.first.collect{|id| res_hash[id]}
        end
        res
      end

      def operation_labels
        @operations ||= []
      end

      # Check if exports should be used for making decisions about propagation.
      #
      # @return [Boolean] Whether or not exports are defined.
      def obey_exports?
        !@exports.nil?
      end

      # List exports
      #
      # @return [Array] the list of defined exports
      def exports
        @exports && @exports.to_a
      end

      def versioned?
        @versioned == true
      end

      # Give us something to watch that will apply to any change
      def versioned!
        @versioned = true
        key :version, BSON::ObjectId, :default => lambda { BSON::ObjectId.new }
      end
    end
    
    included do
      # For some reason I can't simply include MongoMapper::Document. I need to
      # defer it until MongoPercolator::Node itself is included because I
      # think MongoMapper::Document assumes that it's getting included into a 
      # class and not another module.
      instance_eval do 
        include MongoMapper::Document
      end
      extend DSL
      # If I had named the module ClassMethods, it would have been included by
      # ActiveSupport::Concern, but the methods would have been overridden by 
      # MongoMapper::Document, whereas I want these to override those, so I
      # used a different name.
      extend ClassMethodsLate
      common_setup
      setup
    end

    #-----------------
    # Instance methods
    #-----------------

    def versioned?
      self.class.versioned?
    end

    # Since operations are created in the 'nieve' state, they must be released after the
    # node is created. This prevents the operations from getting performed before their
    # nodes are in existence.
    def release_operations
      self.class.operation_labels.each do |op_name|
        op = send(op_name)
        op.mature! unless op.nil? or op.available?
      end
    end

    # Update the version identifier
    def bump_version
      self.version = BSON::ObjectId.new
    end

    # Check to see if any other nodes depend on this one and if so, cause them 
    # to update. This is usually invoked as a before_save callback. Currently, 
    # it's only when a parent is saved that downstream nodes will get updated.
    #
    # @param options [Hash] Can be the following options:
    #   * :force => true - force propagation
    #   * :against => [Hash] - provide a hash against which to make a diff
    # @return [Boolean] whether the callback chain should continue
    def propagate(options = {})
      run_callbacks :propagation do
        bump_version if versioned?
        # If not saved, then we can't have anything else that depends on us.
        next if not persisted?
  
        force = options[:force] || false
  
        # relevant_changes_for() will make a diff against the persisted copy of
        # ourselves. So rather than look up our persisted copy each time, we provide
        # something to diff against, unless against was already provided.
        against = options[:against] || self.class.find(id)
  
        # If we have exports defined, then we only propagate if something that's
        # exported changes.
        if obey_exports? and !force
          self_diff = diff :against => against  # cache the result of the diff method
          next unless exports.select{|exp| self_diff.changed? exp}.length > 0
        end
  
        # Since I only need the class to check dependencies, I don't instantiate the
        # operation until I need to, as this is much faster. Since whether an operation
        # depends on a change in a parent is class-specific, I can cache the results
        # for each class, so I don't need to perform the the check every instance of
        # the same operation class.
        opts = {:fields => %w(_id _type parents)}
        affected_operation_classes_cache = {}
  
        # Only expire operations that have id as a parent, and which are not yet
        # already expired.
        selector = {'parents.ids' => id, 'stale' => false}
        MongoPercolator::Operation.collection.find(selector, opts).each do |op_doc|
          # If we (the parent) have changed in ways that are meaningful to this
          # operation, then we cause the relevant computed properties to be 
          # recomputed. 
          op_class_name = op_doc['_type']
          unless force
            if affected_operation_classes_cache[op_class_name].nil?
              op_class = op_class_name.constantize
              parent_label = op_class.parent_label id, op_doc['parents']
              changes = op_class.relevant_changes_for parent_label, self,
                :against => against
              affected_operation_classes_cache[op_class_name] = !changes.empty?
            end
          end
  
          if force or affected_operation_classes_cache[op_class_name]
            op = MongoPercolator::Operation.from_mongo(op_doc)
            op.expire!
          end
        end
      end
      return true
    end

    def propagate_destroy
      # Handle the case in which this node is getting destroyed
      return unless destroyed?

      MongoPercolator::Operation.find_each('parents.ids' => id) do |op|
        op.remove_parent id
        op.expire!
        op.save!
      end
      return true
    end

    # The instane method self_class returns self.class, so I can have instance
    # versions of class emthods.
    def self_class
      self.class
    end
  end
end
