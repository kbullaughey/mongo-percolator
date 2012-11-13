require 'spec_helper'

describe MongoPercolator::Summary do
  it "can be initialized and has defaults" do
    summary = MongoPercolator::Summary.new
    summary.operations.should == 0
  end

  it "can have the counters incremented" do
    summary = MongoPercolator::Summary.new
    summary.operations += 1
    summary.operations.should == 1
  end
end

# END
