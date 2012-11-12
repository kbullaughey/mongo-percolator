module MongoPercolator
  class Tracker
    include MongoMapper::Document

    # Each tracker belongs to an operation, for which it tracks the state
    belongs_to :operation

    # The above two states should only be changed using the atomic operations 
    # below:

  end
end
