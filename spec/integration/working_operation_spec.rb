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
      parent :animals
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

  describe "RealOp" do
    before :each do
      @animals = Animals.new
      @op = RealOp.new
    end

    it "persists the parent on assignment" do
      @op.animals = @animals
      @animals.persisted?.should be_true
      Animals.where(:id => @animals.id).count.should == 1
    end

    it "can access the parent using the reader" do
      @op.animals = @animals
      @op.animals.should == @animals
    end

    it "knows about its computed property" do
      RealOp.computed_properties.should include(:pets)
    end

    it "has a one association" do
      @op.should respond_to(:some_node)
    end

    it "has the correct count of parents" do
      RealOp.parent_count.should == 1
    end

    it "cannot be added to another class" do
      expect {
        class SomeOtherNode
          include MongoMapper::Document
          include MongoPercolator::Node
          operation RealOp
        end
      }.to raise_error(MongoPercolator::Collision)
    end
  end

  describe "SomeNode" do
    before :each do
      @node = SomeNode.new
      @op = RealOp.new :animals => Animals.new
    end

    it "has a belongs_to association" do
      @node.should respond_to(:real_op)
      @node.should respond_to(:real_op_id)
    end
    
    it "has a real op associated" do
      @node.real_op = @op
      @node.real_op.should be_kind_of(RealOp)
    end

    it "has the keys associated with computed properties" do
      @node.should respond_to(:pets)
    end
  end
end
