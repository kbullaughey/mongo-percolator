require 'spec_helper'

describe "MongoPercolator integration" do
  before :all do
    class MongoPercolatorIntegrationOp1 < MongoPercolator::Operation
      emit {}
    end
  end
end

# END
