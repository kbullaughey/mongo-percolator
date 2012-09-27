module MongoPercolator
  # Instances of this class store copies of many-to-many id lists. This copy 
  # is currently only used to track deletions of the associated objects.
  module Many
    def self.update_many_copy_for(doc)
      many_class = MongoMapper::Plugins::Associations::ManyAssociation
      doc.associations.each do |label,association|
        if association.kind_of? many_class
          # Only worry about many-to-many associations using the :in option.
          next unless association.in_array?

          raise MissingData unless association.options[:in]
          ids_label = association.options[:in]
          ids = doc.send ids_label

          # Handle the case in which the association is not embedded.
          if root? doc
            Copy.create! :node => doc, :path => ids_label.to_s, :ids => ids
          end
        end
      end
    end

    def self.root?(doc)
      doc._root_document == doc
    end

    def self.delete_id(id)
      raise TypeError, "Expecting ObjectId" unless id.kind_of? BSON::ObjectId
      # Loop over the Many::Copy instances that contain id
      Copy.where(:ids => id).find_each do |copy|
        copy.delete_id id
      end
    end

    class Copy
      include MongoMapper::Document
      set_collection_name 'mongo_percolator.manys'
  
      key :ids, Array, :default => []
      belongs_to :node, :polymorphic => true
      key :path, String, :required => true

      validate :check_node

      # Remove the id from the Many::Copy instance and from the original node.
      def delete_id(id)
        doc = doc_at_path
        ids_in_doc = doc.send property
        raise TypeError, "Expecting array" unless ids_in_doc.kind_of? Array
        ids_in_doc.delete id
        doc.save!
        ids.delete id
        save!
      end

      # Determine if we'll be looking into the document or at the root.
      def nested?
        path.include? "."
      end

      # Get the last segment of the path, this is the key for the ids.
      def property
        path.split(".").last
      end

      # Get the possibly nested document where the ids are stored.
      def doc_at_path
        raise MissingData, "No node associated" if node.nil?
        if nested?
          raise NotImplemenetedError, "multi-layer paths not supported"
        else
          doc = node
        end
        doc or raise MissingData, "Failed to resolve path" 
      end

    private
      # Make sure we have a node associated.
      def check_node
        errors.add :node, "Must have a node" if node_id.nil?
      end
    end
  end
end
