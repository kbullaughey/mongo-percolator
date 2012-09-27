require 'spec_helper'

describe MongoPercolator::Many::Copy do
  let(:copy) { FactoryGirl.build('mongo_percolator/many/copy').dup }

  before :all do
    class MonyCopyTestClass1
      include MongoMapper::Document
    end
  end

  it { should respond_to(:ids) }
  it { should respond_to(:root) }
  it { should respond_to(:root_id) }
  it { should respond_to(:path) }
  it { should respond_to(:label) }

  it "can be saved with factory defaults" do
    copy.save.should be_true
  end

  it "fails to be saved without a label" do
    copy.label = nil
    copy.save.should be_false
    copy.errors[:label].should_not be_nil
  end

  it "fails to be saved without a root" do
    copy.root_id = nil
    copy.save.should be_false
    copy.errors[:root].should_not be_nil
  end
end
