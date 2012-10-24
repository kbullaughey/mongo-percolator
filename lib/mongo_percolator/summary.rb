module MongoPercolator
  class Summary
    attr_accessor :iterations, :operations
    
    def initialize
      @iterations = 0
      @operations = 0
    end
  end
end
