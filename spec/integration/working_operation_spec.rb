require 'spec_helper'

describe "MongoPercolator Node & Operation integration" do
  before :all do
    # This will serve as the parent class
    class Animals
      include MongoMapper::Document
      def wild
        ["sloth", "binturong"]
      end
      def farm
        ["pig"]
      end
    end

    # Set up an operation class with a few computed properties
    class RealOp < MongoPercolator::OperationDefinition
      def emit(inputs)
      end
      belongs_to :animals
      computes(:pets) { key :pets, Array }
      depends_on 'animals.farm'
      depends_on 'animals.wild'
    end

    # Set up a node class
    class SomeNode
      include MongoMapper::Document
      include MongoPercolator::Node
      operation RealOp
    end
  end

  describe "SomeNode" do
    before :each do
      @node = SomeNode.new
      @node.real_op = RealOp.new :animals => Animals.new
    end

    it "has a real op associated" do
      @node.real_op.should be_kind_of(RealOp)
    end
  end
end
