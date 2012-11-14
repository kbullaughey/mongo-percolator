module MongoPercolator
  class Guide
    attr_accessor :operations
    
    def initialize
      reset
    end

    def interrupt!
      @received_interrupt = true
    end

    def interrupted?
      @received_interrupt == true
    end

    def percolate
      reset
      loop do
        break if interrupted?
        Operation.acquire_and_perform or break
        self.operations += 1
      end
      self
    end

    def reset
      @operations = 0
      @received_interrupt = false
    end
  end
end
