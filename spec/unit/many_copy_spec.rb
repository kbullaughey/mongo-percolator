require 'spec_helper'

describe MongoPercolator::Many::Copy do
  let(:copy) { FactoryGirl.build('mongo_percolator/many/copy').dup }

  before :all do
    class MonyCopyTestClass1
      include MongoMapper::Document
    end
  end

  it { should respond_to(:ids) }
  it { should respond_to(:node) }
  it { should respond_to(:node_id) }
  it { should respond_to(:path) }

  it "can be saved with factory defaults" do
    copy.save.should be_true
  end

  it "fails to be saved without a path" do
    copy.path = nil
    copy.save.should be_false
  end

  it "fails to be saved without a node" do
    copy.node_id = nil
    copy.save.should be_false
  end

  it "knows the last segment of a one-layer path" do
    copy.path = "level1"
    copy.property.should == "level1"
  end

  it "knows the last segment of a two-layer path" do
    copy.path = "level1.level2"
    copy.property.should == "level2"
  end

  it "knows a one-layer path is not nested" do
    copy.path = "level1"
    copy.nested?.should be_false
  end

  it "knows a two-layer path is nested" do
    copy.path = "level1.level2"
    copy.nested?.should be_true
  end
end
