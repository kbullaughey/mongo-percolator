# encoding: UTF-8
module MongoMapper
  module Plugins
    module Sci
      module ClassMethods
        # I override this method so that it works with upserts.
        def criteria_hash(criteria={})
          criteria = criteria.merge(:_type => name) if single_collection_inherited?
          super criteria
        end   

        # This a fix for upserts in order to get new documents to incorporate 
        # the default query parameters (including _type) and to get it to work
        # with mongo mapper percolation. Note that the document will always end
        # up with the _type of the class on which it's called. So this method
        # should only be used to update existing documents of the same _type as
        # inferred from the class name on which this is called.
        def where(*args)
          # extra will include _type if the document uses sci, per the above
          # overridden criteria_hash method.
          extra = criteria_hash.to_hash
          node_class = self

          # We tap into the result of super (which processes args), and add a
          # singleton method, upsert, so we can upsert, if we want to.
          #
          # For upserts to work as expected, it's important that the query
          # identify a unique document. Otherwise, only the first matching document
          # will be updated. In some cases a second query must be done in order
          # to percolate changes, if the query matches multiple documents, the one
          # for which changes are percolated may not be the same as the one that
          # was just modified.
          super.tap do |q|
            q.define_singleton_method :upsert do |mod|
              # We get the query from plucky
              query = criteria.to_hash

              # The modification is passed in as a hash to the upsert method,
              # which we duplicate.
              mod = mod.clone

              # We first try and do a find_and_modify, this will give us access
              # to the old document, so it can be used in a diff, in order to 
              # decide if the changes need to be percolated.
              original = node_class.find_and_modify(:query => query, :update => mod)
              # If we fail to modify an existing document, then then we do an
              # upsert. This accounts for the possibility that the document was
              # created in the meantime by concurrently executing code.
              if original.nil?
                if mod.key? :$set
                  mod[:$set].merge! extra
                else
                  mod[:$set] = extra
                end
                action_summary = update(mod, :upsert => true)
                raise MongoPercolator::DatabaseError.new("Update error").add(:mod => mod) unless
                  action_summary["err"].nil?
                if action_summary["updatedExisting"] == false
                  node = node_class.find(action_summary["upserted"])
                  # Run the callbacks. Note that the document will be checked for
                  # whether it needs to propagate changes, but this will generally
                  # not result in any propagation (unless the document has been 
                  # subsequently modified) because the document will not show any
                  # changes. This will cause both the create and save callbacks to run
                  node.run_callbacks(:create) { node.save! }
                else
                  # The document that didn't exist just a moment ago (when we
                  # did find_and_modify) was created in the meantime and so
                  # was updated (not upserted). This should be a rare condition
                  # and so we propagate changes for the first document that
                  # matches our original query. If this query is doesn't not
                  # uniquely identify a document, it's possible the wrong document
                  # will be percolated. This is such an edge case, I'm not going
                  # to worry about it.
                  #
                  # Also, if the update operation modified properties of the
                  # document that were used in the query, this query here might
                  # not work.
                  node = node_class.where(query).first
                  raise MongoPercolator::MissingData.new("Missing updated node").
                    add(:mod => mod) if node.nil?
                  # Force propagation
                  node.propagate :force => true
                end
              else
                node = node_class.find original.id
                raise MongoPercolator::MissingData.new("Missing updated node").
                  add(:id => original.id) if node.nil?
                # Trigger the save callbacks this won't actually cause
                # propagation, unfortunately, it does require additional
                # database access and construction of a diff.
                node.save!
                # Propagate diffing against the original document, so that percolation only happens if
                # the differences matter to the dependent operations.
                node.propagate :against => original
              end
            end
          end
        end
      end
    end
  end
end
