require 'spec_helper'

describe MongoPercolator::Guide do
  before :each do
    @guide = MongoPercolator::Guide.new
  end

  it "can be initialized and has defaults" do
    expect(@guide.operations).to eq(0)
    expect(@guide.interrupted?).to be false
  end

  it "can have the counters incremented" do
    @guide.operations += 1
    expect(@guide.operations).to eq(1)
  end

  it "can store information about an interrupt" do
    @guide.interrupt!
    expect(@guide.interrupted?).to be true
  end

  it "starts off with a nil percolation time" do
    expect(@guide.percolation_time).to be_nil
  end

  it "knows how long it percolated for" do
    @guide.percolate
    expect(@guide.percolation_time).to be > 0
  end
end

# END
