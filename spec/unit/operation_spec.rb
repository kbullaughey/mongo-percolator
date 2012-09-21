require 'spec_helper'

describe "MongoPercolator::Operation unit" do
  before :all do
    # Set up a derived class with no computed properties
    class NoOp < MongoPercolator::Operation
    end

    class AnimalsUnit
      def wild
        ["sloth", "binturong"]
      end
      def farm
        ["pig"]
      end
    end

    # Set up a derived class with a few computed properties
    class RealOp < MongoPercolator::Operation
      def emit(inputs)
      end
      key :animals, AnimalsUnit
      computes(:pets) { key :pets, Array }
      depends_on 'animals.farm'
      depends_on 'animals.wild'
    end
  end

  describe "NoOp" do
    it "shouldn't have any computed properties" do
      NoOp.computed_properties.should == {}
    end

    it "propagation fails when given a non-parent" do
      non_parent = double(:id => 'xyz')
      expect {
        NoOp.new.propagate non_parent
      }.to raise_error(ArgumentError)
    end
  end

  describe "RealOp" do
    it "should have pets as a computed property" do
      RealOp.computed_properties.should include(:pets)
    end

    it "can gather the data for the operation" do
      node = double(:animals => AnimalsUnit.new)
      data = RealOp.new.gather node
      data.should be_kind_of(Hash)
      data['animals.farm'].should == ["pig"]
      data['animals.wild'].should == ["sloth", "binturong"]
    end
  end
end
