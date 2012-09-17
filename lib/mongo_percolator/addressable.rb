module MongoPercolator
  module Addressable
    # Get data assuming that the dot-separated path is a valid method chain
    def fetch(path, target = self)
      pieces = path.split "."
      while !pieces.empty?
        target = target.send pieces.shift
      end
      target
    end
  end
end
