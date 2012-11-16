require 'spec_helper'

describe MongoPercolator::Guide do
  before :each do
    @guide = MongoPercolator::Guide.new
  end

  it "can be initialized and has defaults" do
    @guide.operations.should == 0
    @guide.interrupted?.should be_false
  end

  it "can have the counters incremented" do
    @guide.operations += 1
    @guide.operations.should == 1
  end

  it "can store information about an interrupt" do
    @guide.interrupt!
    @guide.interrupted?.should be_true
  end
end

# END
