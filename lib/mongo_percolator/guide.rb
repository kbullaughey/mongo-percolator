module MongoPercolator
  # Provides an interface to percolation that keeps track of several statistics
  # and allows percolation to be interrupted in a way that allows the present 
  # operation to complete.
  class Guide
    attr_accessor :operations, :started_at, :ended_at
    
    # Instantiate a guide.
    def initialize
      reset
    end

    # Interrupt percolation. The current operation will complete, but no 
    # additional ones will be performed.
    def interrupt!
      @received_interrupt = true
    end

    # Test whether percolation is interrupted
    def interrupted?
      @received_interrupt == true
    end

    # Percolate until there are no more operations or its interrupted.
    def percolate
      reset
      self.started_at = Time.now.utc
      loop do
        break if interrupted?
        res = Operation.acquire_and_perform
        break unless res
        self.operations += 1
        break if operations >= 100
      end
      self.ended_at = Time.now.utc
      self
    end

    # Reset the statistics that the guide keeps regarding percolation. This is
    # called automatically in most cases.
    def reset
      @started_at = nil
      @ended_at = nil
      @operations = 0
      @received_interrupt = false
    end

    # Return the time spent percolating in seconds.
    def percolation_time
      return nil if started_at.nil? or ended_at.nil?
      ended_at - started_at
    end
  end
end
