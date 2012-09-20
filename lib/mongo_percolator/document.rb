module MongoPercolator
  # Enhanced document mixin.
  module Document
    include MongoPercolator::Addressable

    # For some reason I can't simply include MongoMapper::Document. I need to 
    # defer it until MongoPercolator::Document itself is included because I
    # think MongoMapper::Document assumes that it's getting included into a 
    # class and not another module.
    def self.included(mod)
      mod.instance_eval do
        include MongoMapper::Document
      end
    end
  end
end
