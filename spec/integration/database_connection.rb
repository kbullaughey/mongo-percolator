require 'spec_helper'

describe "Test database connection" do
  before :all do
    class TestObject
      include MongoMapper::Document
      key :stuff, String
    end
  end

  it "is connected" do
    MongoMapper.connection.connected?.should be_true
  end

  it "can create an object" do
    o = TestObject.new :stuff => "miscellaneous"
    o.save!.should be_true
  end
end
