require 'spec_helper'

describe MongoPercolator::Many::Copy do
  let(:copy) { FactoryGirl.build('mongo_percolator/many/copy').dup }

  before :all do
    class MonyCopyTestClass1
      include MongoMapper::Document
    end
  end

  it { expect(subject).to respond_to(:ids) }
  it { expect(subject).to respond_to(:root) }
  it { expect(subject).to respond_to(:root_id) }
  it { expect(subject).to respond_to(:path) }
  it { expect(subject).to respond_to(:label) }

  it "can be saved with factory defaults" do
    expect(copy.save).to be true
  end

  it "fails to be saved without a label" do
    copy.label = nil
    expect(copy.save).to be false
    expect(copy.errors[:label]).to_not be_nil
  end

  it "fails to be saved without a root" do
    copy.root_id = nil
    expect(copy.save).to be false
    expect(copy.errors[:root]).to_not be_nil
  end
end
