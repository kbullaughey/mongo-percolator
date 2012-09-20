module MongoPercolator
  module Addressable
    # A record of what's different between a persisted mongo object and a 
    # potentially modified instance. An instance of this class is used to
    # inquire about whether particular addresses have changed. If an object
    # has not been persisted, then all valid addresses appear changed. In
    # practice, this is unimportant because only persisted objects are likely
    # to be queried for changes as they're found by ID in the graph.
    class Diff
      attr_reader :diff, :live, :stored

      # Create a diff of the document against the persisted copy.
      #
      # @param object [MongoMapper::Document] Subject of the diff.
      def initialize(doc)
        @live = doc
        if persisted?
          @stored = doc.class.find(doc.id)
          live_mongo = MongoPercolator::dup_hash_without_ids @live.to_mongo
          persisted_mongo = MongoPercolator::dup_hash_without_ids @stored.to_mongo
          @diff = live_mongo.diff persisted_mongo
        end
      end

      # Check if the value at the address has changed. When checking a 
      # multi-level address. It's only the object at the full address that
      # matters. For example, if an association has changed, but a key on that
      # association is still nil, then it's as if the full address to that key
      # hasn't changed, even if the associated object has changed.
      #
      # @param addr [String] Address to check.
      # @return [Boolean] whether the persisted and live copies differ.
      def changed?(addr)
        return true if not persisted?
        live_val = Addressable.fetch(addr, :target => live)
        persisted_val = Addressable.fetch(addr, :target => stored)
        live_val != persisted_val
      end

      # Indicate whether the document on which the diff is based is persisted.
      #
      # @return [Boolean] Whether it's persisted.
      def persisted?
        live.persisted?
      end
    end
  end
end

