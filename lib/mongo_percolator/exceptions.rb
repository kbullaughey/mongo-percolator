module MongoPercolator
  # Used when something is missing from the mongo database
  class MissingData < StandardError; end
  class Collision < StandardError; end
  class ShouldBeImpossible < StandardError; end
end
