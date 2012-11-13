module MongoPercolator
  class Summary
    attr_accessor :operations
    
    def initialize
      @operations = 0
    end
  end
end
