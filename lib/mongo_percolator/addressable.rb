module MongoPercolator
  # Addressalbe can be used either as a standalone module or mixed into a class.
  module Addressable

    class InvalidAddress < StandardError; end

    # Use Forwardable to create instance versions that pass through to the 
    # corresponding class methods
    extend Forwardable
    def_delegators Addressable, :match_head, :head, :tail

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
    def diff(options={})
      raise ArgumentError, "expecting a hash" unless options.kind_of? Hash
      use_cached = options[:use_cached] || false
      @diff = Diff.new self if @diff.nil? or !use_cached
      @diff
    end

    #---------------------------------
    # Class methods for standalone use
    #---------------------------------

    # Return a proc that can be used to match head on the front of a address.
    #
    # @param h [String] First property in the address.
    # @return [Proc] Proc that can be used to match an address against the head
    def self.match_head(h)
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
    # @param addr [String] Address to fetch on `target`.
    # @param options [Hash]
    #   :target [Object] - Where to start looking for `addr`
    #   :raise_on_invalid [Boolean] - Whether or not invalid addresses should
    #     raise an error, or just return nil (default).
    # @return [Object] Whatever the address points to.
    def self.fetch(addr, options = {})
      raise ArgumentError, "expecting a hash" unless options.kind_of? Hash
      target = options[:target]
      raise ArgumentError, "No target" if target.nil?
      raise_on_invalid = options[:raise_on_invalid] || false
      p = pieces(addr)
      while !p.empty?
        segment = p.shift
        if target.kind_of? Hash
          if target.include? segment.to_s
            target = target[segment.to_s]
          elsif target.include? segment.to_sym
            target = target[segment.to_sym]
          else
            raise InvalidAddress, "key #{segment} missing" if raise_on_invalid
            return nil
          end
        else
          if target.respond_to? segment
            target = target.send segment
          else
            raise InvalidAddress, "method #{segment} missing" if raise_on_invalid
            return nil
          end
        end
      end
      target
    end
  end
end
