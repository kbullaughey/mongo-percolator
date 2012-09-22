require 'spec_helper'

describe "MongoPercolator Node & Operation integration" do
  before :all do
    # This will serve as the parent class
    class AnimalsIntegration
      include MongoPercolator::Node
      key :wild, Array
      key :farm, Array
      key :imaginary, Array
    end

    # Set up an operation class with a few computed properties
    class RealOp < MongoPercolator::Operation
      emit do
        self.pets = (inputs['animals.farm'] + inputs['animals.wild']).sort
      end
      parent :animals, :class => AnimalsIntegration
      computes(:pets) { key :pets, Array }
      computes(:address)
      depends_on 'animals.farm'
      depends_on 'animals.wild'
    end

    # Set up a node class
    class SomeNode
      include MongoPercolator::Node
      operation :real_op, RealOp
    end
  end

  describe "RealOp" do
    before :each do
      AnimalsIntegration.remove
      MongoPercolator::Operation.remove
      SomeNode.remove
      @animals = AnimalsIntegration.new
      @op = RealOp.new
    end

    it "is frozen" do
      RealOp.parents.frozen?.should be_true
    end

    it "persists the parent on assignment" do
      @op.animals = @animals
      @animals.persisted?.should be_true
      AnimalsIntegration.where(:id => @animals.id).count.should == 1
    end

    it "can access the parent using the reader" do
      @op.animals = @animals
      @op.animals.should == @animals
    end

    it "knows about its computed property" do
      RealOp.computed_properties.should include(:pets)
    end

    it "knows a computed property lacks a block" do
      RealOp.computed_properties.should include(:address)
      RealOp.computed_properties[:address].should be_nil
    end

    it "has a one association" do
      @op.should respond_to(:node)
    end

    it "has the correct count of parents" do
      RealOp.parent_count.should == 1
    end

    it "cannot be added to another class" do
      expect {
        class SomeOtherNode
          include MongoPercolator::Node
          operation :real_op, RealOp
        end
      }.to raise_error(MongoPercolator::Collision)
    end

    it "fails when passed a malformed label" do
      expect {
        class YetAnotherNode
          include MongoPercolator::Node
          operation :"not okay", RealOp
        end
      }.to raise_error(ArgumentError, /Malformed label/)
    end

    it "fails when not passed a class as the second param" do
      expect {
        class YetAnotherNode
          include MongoPercolator::Node
          operation :label, "not a class"
        end
      }.to raise_error(ArgumentError, /Expecting class/)
    end

    context "populated AnimalsIntegration" do
      before :each do
        @animals = AnimalsIntegration.new :wild => %w(sloth binturong)
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
      @animals = AnimalsIntegration.new :wild => %w(sloth binturong dugong)
      @op = RealOp.new :animals => @animals
    end

    it "has an operation association" do
      @node.should respond_to(:real_op)
    end
    
    it "has the keys associated with computed properties" do
      @node.should respond_to(:pets)
    end

    context "has an op associated" do
      before :each do
        @node.real_op = @op
      end

      it "has a real op associated" do
        @node.real_op.should be_kind_of(RealOp)
      end

      it "can find the node from the real op" do
        @op.node.should be_kind_of(SomeNode)
      end
  
      it "can computed computed properties on demand" do
        @node.pets.should == []
        @op.recompute!
        @node.reload
        @node.pets.should == %w(binturong dugong sloth)
      end

      context "computed initially" do
        before :each do
          @op.recompute!
          @node.reload
        end

        it "should be marked as old when the parent is changed" do
          @animals.farm = ['hog']
          @animals.save
          @node.reload
          @node.real_op.old?.should be_true
        end
    
        it "gets an updated computed property when the parent is changed" do
          @animals.farm = ['hog']
          @animals.save
          MongoPercolator::Operation.where(:_old => true).count.should == 1
          MongoPercolator.percolate
          @node.reload
          @node.pets.should == %w(binturong dugong hog sloth)
        end

        it "is no longer marked as old after percolation" do
          @animals.farm = ['hog']
          @animals.save
          MongoPercolator.percolate
          @node.reload
          @node.real_op.old?.should be_false
        end

        it "only takes the number of passes needed" do
          @animals.farm = ['hog']
          @animals.save
          passes_made = MongoPercolator.percolate 10
          passes_made.should == 1
        end
      end
    end
  end

  pending "check that multiple parents of same class work (#{__FILE__})"
  pending "check parents can be out of order when using :position (#{__FILE__})"
  pending "check that parents can have gaps when using :position (#{__FILE__})"
  pending "check that computes can compute vaious associations (#{__FILE__})"
end
