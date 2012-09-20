require 'spec_helper'

describe "MongoPercolator Node & Operation integration" do
  before :all do
    # This will serve as the parent class
    class Animals
      include MongoPercolator::Document
      key :wild, Array
      key :farm, Array
      key :imaginary, Array
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
      include MongoPercolator::Node
      operation RealOp
    end
  end

  describe "RealOp" do
    before :each do
      Animals.remove
      MongoPercolator::OperationDefinition.remove
      SomeNode.remove
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

    context "populated Animals" do
      before :each do
        @animals = Animals.new :wild => %w(sloth binturong)
        @animals.save!
        @op.animals = @animals
      end

      it "knows which dependencies have changed (1)" do
        @animals.wild << 'meerkat'
        @op.relevant_changes_for(@animals).should == ['animals.wild']
      end
  
      it "knows which dependencies have changed (2)" do
        @animals.wild << 'meerkat'
        @animals.farm = ['pig']
        @op.relevant_changes_for(@animals).sort.should == 
          %w(animals.farm animals.wild)
      end
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

  pending "check that multiple parents of same class work (#{__FILE__})"
  pending "check parents can be out of order when using :position (#{__FILE__})"
  pending "check that parents can have gaps when using :position (#{__FILE__})"
end
