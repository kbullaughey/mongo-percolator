module MongoPercolator
  # Addressalbe can be used either as a standalone module or mixed into a class.
  module Addressable

    # Use Forwardable to create instance versions that pass through to the 
    # corresponding class methods
    extend Forwardable
    def_delegators :Addressable, :match_head, :head, :tail

    #---------------------------
    # Instance methods for mixin
    #---------------------------

    def changed?(addr, target=self)
      Addressable.changed? addr, target
    end

    def fetch(addr, target=self)
      Addressable.fetch addr, target
    end

    #---------------------------------
    # Class methods for standalone use
    #---------------------------------

    # Indicate whether data at an address has changed, assumes that target
    # implements the requisite _changed? functions. This method checks each
    # layer in the address to see if it's changed.
    # @raises [NameError] When a requisite _changed method is not implemented.
    def self.changed?(addr, target)
    end

    # Return a proc that can be used to match head on the front of a address.
    def self.match_head(h)
      Proc.new {|addr| head(addr) == h }
    end

    # Return the first piece of the address.
    def self.head(addr)
      addr.split(".").first
    end

    # Return everything but the head
    def self.tail(addr)
      pieces = addr.split(".")
      pieces.shift
      pieces.join "."
    end

    # Get data assuming that the dot-separated address is a valid method chain
    def self.fetch(addr, target)
      pieces = addr.split "."
      while !pieces.empty?
        target = target.send pieces.shift
      end
      target
    end
  end
end
