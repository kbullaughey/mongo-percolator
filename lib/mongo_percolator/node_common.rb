module MongoPercolator
  module NodeCommon
    include MongoPercolator::Addressable
    module DSL
    end
    module ClassMethods
      def setup
        after_save :refresh_many_ids
        before_destroy :remove_references_to_me
      end
    end
  end
end
