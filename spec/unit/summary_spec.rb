require 'spec_helper'

describe MongoPercolator::Summary do
  before :each do
    @summary = MongoPercolator::Summary.new
  end

  it "can be initialized and has defaults" do
    @summary.operations.should == 0
    @summary.interrupted?.should be_false
  end

  it "can have the counters incremented" do
    @summary.operations += 1
    @summary.operations.should == 1
  end

  it "can store information about an interrupt" do
    @summary.interrupt!
    @summary.interrupted?.should be_true
  end
end

# END
