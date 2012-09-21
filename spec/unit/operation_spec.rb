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
    class RealOpUnit < MongoPercolator::Operation
      emit {}
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

    it "finalize fails without emit block" do
      expect {
        NoOp.finalize
      }.to raise_error(NotImplementedError, /emit/)
    end
  end

  describe "RealOpUnit" do
    it "can be finalized" do
      expect { RealOpUnit.finalize }.to_not raise_error
    end

    it "should have pets as a computed property" do
      RealOpUnit.computed_properties.should include(:pets)
    end

    it "can gather the data for the operation" do
      op = RealOpUnit.new :animals => AnimalsUnit.new
      data = op.gather
      data.should be_kind_of(Hash)
      data['animals.farm'].should == ["pig"]
      data['animals.wild'].should == ["sloth", "binturong"]
    end
  end
end
