module MongoPercolator
  # Plugin for MongoMapper that adds find_and_modify support
  module FindAndModifyPlugin
    extend ActiveSupport::Concern
    
    module ClassMethods
      def find_and_modify(options)
        opts = options.dup
        criteria = opts.delete :query
        raise ArgumentError, "Must provide query" if criteria.nil?
        # Merge in stuff from MongoMapper/Plucky, but exclude all special keys
        base_query = query.to_hash.
          reject{|k,v| Plucky::Query::OptionKeys.include? k}
        opts[:query] = base_query.merge(criteria)
        load collection.find_and_modify(opts) 
      end
    end
  end
end
