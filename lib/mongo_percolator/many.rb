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

          ids_label = association.options[:in].to_s
          ids = doc.send ids_label

          path = doc.root? ? nil : doc.path_to_root

          # Either edit an existing document or make a new one
          selector = {:node_id => doc.id, :label => ids_label}
          many_copy = Copy.where(selector).first || Copy.new(selector)

          # Update it with the current info
          many_copy.root = doc.find_root
          many_copy.path = path
          many_copy.ids = ids

          many_copy.save
        end
      end
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
      belongs_to :root, :polymorphic => true
      key :node_id, BSON::ObjectId
      key :path, String
      key :label, String, :required => true

      validate :check

      # Remove the id from the Many::Copy instance and from the original node.
      def delete_id(id)
        ids_in_doc = root.fetch(full_path)
        raise TypeError, "Expecting array" unless ids_in_doc.kind_of? Array
        ids_in_doc.delete id
        root.save!
        ids.delete id
        save!
      end

      def full_path
        [path, label].compact.join "."
      end

    private
      # Make sure we have a root associated.
      def check
        errors.add :root, "Must have a root node" if root_id.nil?
      end
    end
  end
end
