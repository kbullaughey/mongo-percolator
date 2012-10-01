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
      # @param doc [MongoMapper::Document] Subject of the diff.
      # @param against [Hash] If provided, this will be used as if it were the 
      #   persisted copy.
      def initialize(doc, against = nil)
        @live = doc
        if against.nil?
          @stored = persisted? ? doc.class.find(doc.id) : {}
        else
          @stored = against
        end

        live_mongo = MongoPercolator::dup_hash_selectively @live.to_mongo
        persisted_mongo = MongoPercolator::dup_hash_selectively @stored.to_mongo
        @diff = live_mongo.diff persisted_mongo
      end

      # Check if the value at the address has changed. When checking a 
      # multi-level address. It's only the object at the full address that
      # matters. For example, if an association has changed, but a key on that
      # association is still nil, then it's as if the full address to that key
      # hasn't changed, even if the associated object has changed.
      #
      # @param addr [String] Address to check (optional). If no address is given
      #   then the whole object is used.
      # @param options [Hash] Options appropriate for passing to fetch
      # @return [Boolean] whether the persisted and live copies differ.
      def changed?(addr = nil, options = {})
        a = Addressable
        return !@diff.empty? if addr.nil?
        addr = addr.to_s
        live_val = a.fetch(addr, a.use_target(live, options))
        persisted_val = a.fetch(addr, a.use_target(stored, options))
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

