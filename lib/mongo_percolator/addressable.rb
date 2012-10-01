module MongoPercolator
  # Addressalbe can be used either as a standalone module or mixed into a class.
  module Addressable

    class InvalidAddress < StandardError; end

    # Use Forwardable to create instance versions that pass through to the 
    # corresponding class methods
    extend Forwardable
    def_delegators Addressable, :match_head, :head, :tail, :pieces, :use_target

    #---------------------------
    # Instance methods for mixin
    #---------------------------

    def fetch(addr, options = {})
      raise ArgumentError, "expecting a hash" unless options.kind_of? Hash
      options[:target] ||= self
      Addressable.fetch(addr, options)
    end

    # Create/use a diff of the object. Unless otherwise indicated, it assumes
    # that it's okay to use a cached copy of the diff it one exists.
    # @param options [Hash] Options hash, which can include:
    #   :use_cached [Boolean] Whether it's okay to use a cached diff (default=false)
    #   :against Object to compare against. If none is given, compare against 
    #     persisted copy (which requries object to be a MongoMapper::Document).
    def diff(options={})
      raise ArgumentError, "expecting a hash" unless options.kind_of? Hash
      use_cached = options[:use_cached] || false
      @diff = Diff.new self, options[:against] if @diff.nil? or !use_cached
      @diff
    end

    #---------------------------------
    # Class methods for standalone use
    #---------------------------------

    # Return a proc that can be used to match head on the front of a address.
    #
    # @param h [String|Symbol] First property in the address.
    # @return [Proc] Proc that can be used to match an address against the head
    def self.match_head(h)
      h = h.to_s if h.kind_of? Symbol
      raise ArgumentError, "expecting string or symbol" unless h.kind_of? String
      Proc.new {|addr| head(addr) == h }
    end

    # Split on the dots
    #
    # @param addr [String] Address to split.
    # @return [Array] Address segments.
    def self.pieces(addr)
      Array(addr.split ".")
    end

    # Return the first piece of the address.
    #
    # @param addr [String] Address of which to get the head.
    # @return [String] First property in the address.
    def self.head(addr)
      pieces(addr).first
    end

    # Return everything but the head
    #
    # @param addr [String] Address of which to take the tail.
    # @return [String] Everything but the first property, nil if no tail.
    def self.tail(addr)
      pieces = pieces(addr)
      pieces.shift
      return nil if pieces.empty?
      pieces.join "."
    end

    # Get data assuming that the dot-separated address is a valid method chain 
    # or series of hash properties.
    #
    # @param addr [String] Address to fetch on `target`. Becuase segments that 
    #   point to arrays without a given index will traverse each item in the 
    #   array, an address can match multiple objects.
    # @param options [Hash]
    #   :target [Object] - Where to start looking for `addr`
    #   :raise_on_invalid [Boolean] - Whether or not invalid addresses should
    #     raise an error, or just return nil (default).
    #   :single [Boolean] - Only match one result. If a non-indexed array
    #     is encountered, then an error is raised.
    # @return [Array] Whatever the pattern matches.
    def self.fetch(addr, options = {})
      raise ArgumentError, "Nil address" if addr.nil?
      raise ArgumentError, "Expecting string" unless addr.kind_of? String
      raise ArgumentError, "Expecting a hash" unless options.kind_of? Hash
      target = options[:target]
      raise ArgumentError, "No target" if target.nil?
      raise_on_invalid = options[:raise_on_invalid] || false

      segment = head(addr)
      remainder = tail(addr)
      raise InvalidAddress, "Invalid segment" unless valid_segment? segment

      # We can address particular array indicies whereby the object has an id 
      # property and we give the id in square brackets.
      if array? segment
        segment, index = array_name(segment), array_index(segment)
      end

      # Handle both addressing into hashes and regular objects (via instance 
      # methods).
      if target.kind_of? Hash
        target = indifferent_hash_get(segment, target, options)
      else
        if target.respond_to? segment
          target = target.send segment
        else
          raise InvalidAddress, "method #{segment} missing" if raise_on_invalid
          target = nil
        end
      end

      # We're done looking if we see a nil
      if target.nil?
        return options[:single] ? nil : [nil]
      end
      
      # If we provided an index, we want to get just that item from the array
      if !index.nil?
        raise TypeError, "Expecting array" unless target.kind_of? Array
        target = find_in_array(index, target, options)
      end

      if options[:single]
        remainder.nil? ? target : fetch(remainder, use_target(target, options))
      elsif remainder.nil?
        # We're done if there is no tail.
        [target]
      elsif target.is_a? Array
        # If at the end, we're left with an array, then we consider the address
        # to match all elements and we traverse each one.
        found = []
        target.each{|item| found += fetch(remainder, use_target(item, options))}
        found
      else
        fetch(remainder, use_target(target, options))
      end
    end

    # Return a new options hash with the target replaced
    def self.use_target(target, options)
      options.merge(:target => target)
    end

    def self.array?(key)
      !!(key =~ /[^\[\]]\[[^\]]+\]/)
    end

    def self.array_name(key)
      key.sub(/\[.*$/, "")
    end

    def self.array_index(key)
      key[/\[([^\]]+)\]/, 1]
    end

    def self.valid_segment?(key)
      !!(key =~ /^[-A-Za-z0-9_?!]+(\[[^\]]+\])?$/)
    end

    def self.indifferent_hash_get(key, hash, options = {})
      if hash.include? key.to_s
        hash[key.to_s]
      elsif hash.include? key.to_sym
        hash[key.to_sym]
      else
        raise InvalidAddress, "key #{key} missing" if
          options[:raise_on_invalid]
        nil
      end
    end

    def self.find_in_array(index, target, options = {})
      items = target.select do |item|
        if item.kind_of? Hash
          indifferent_hash_get(:id, item, options).to_s == index
        else
          item.respond_to?(:id) ? item.send(:id).to_s == index : false
        end
      end
      items.first
    end
  end
end
