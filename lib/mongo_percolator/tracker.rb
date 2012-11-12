module MongoPercolator
  class Tracker
    include MongoMapper::Document

    # Storage for state
    key :state, String

    # Each tracker belongs to an operation, for which it tracks the state
    belongs_to :operation, :class_name => 'MongoPercolator::Operation'

    # Make sure events can't be triggered on mass assignment
    attr_protected :state_event

    # Start the operation out as needing recomputation. I set :action to nil
    # so that save is not called every time I transition. I'll do this manually
    state_machine :state, :initial => :brandnew, :action => nil do
      state :brandnew     # The operation has never been put into stale or fresh
      state :stale        # An operation is stale when it needs recomputation
      state :fresh        # An operation doesn't need recomputation
      state :error        # Some error occurred during recomputation

      # When the operation is in either of these states, it is under the control of
      # a single thread. No other code should be modifying the operation.
      state :holding      # Marked by a percolator daemon for recomputation
      state :computing    # Currently being recomputed
      state :again        # Operation will need to be recomputed again This can
                          #   happen if concurrently executing code changes a
                          #   parent in the middle of recomputation.

      # An error has occurred
      event(:choke) { transition all => :error }

      # A new operation can either start off fresh or stale
      event(:born_fresh) { transition :brandnew => :fresh }
      event(:born_stale) {transition :brandnew => :stale }

      # The operation is out of date. This can happen during computation, in
      # which case the transition is to :again.
      event :expire do 
        transition [:fresh, :stale] => :stale, [:computing, :holding] => :again
      end
      
      # Announce the intention to perform the operation, although if the operation
      # has been subsequently marked :again, then we just return the the stale
      # state. The actual computation is performed by an after_transition callback
      # only in the case when we transition from :holding to :computing.
      event(:perform) { transition :holding => :computing, :again => :stale }

      # Release the operation so others can get grab ahold of it.
      event(:release) { transition :computing => :fresh, :again => :stale }

      # One transition not listed is what I call 'fetch'. This is handled by
      # a find_and_modify query which transitions from :stale => :holding

      # If we manage to transition from :holding to :computing, then we compute
      after_transition :holding => :computing, :do => :compute
    end

    def compute
    end
  end
end
