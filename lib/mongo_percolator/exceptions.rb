# I give all exceptions an optional slot that I can use to put any
# additional data I want to show up in the Exceptional.io output.
class StandardError
  attr_accessor :extra
  def add(x)
    @extra = x
    self
  end
end

module MongoPercolator
  # Used when something is missing from the mongo database
  class MissingData < StandardError; end
  class Collision < StandardError; end
  class ShouldBeImpossible < StandardError; end
  # Used when someone incorrectly uses the DSL
  class DeclarationError < StandardError; end
  class FetchFailed < StandardError; end
  class StateError < StandardError; end
end
