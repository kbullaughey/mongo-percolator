require 'spec_helper'

describe "Test database connection" do
  before :all do
    class TestObject
      include MongoMapper::Document
      key :stuff, String
    end
  end

  it "is connected" do
    expect(MongoMapper.connection.connected?).to be true
  end

  it "can create an object" do
    o = TestObject.new :stuff => "miscellaneous"
    expect(o.save!).to be true
  end
end
