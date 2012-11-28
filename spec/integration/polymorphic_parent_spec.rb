require 'spec_helper'

describe "Polymorphic operation parent integration" do
  before :all do
    class PolymorphicParentA
      include MongoPercolator::Node
      key :common, String
    end

    class PolymorphicParentB
      include MongoPercolator::Node
      key :common, String
    end

    class NodeWithPolymorphicParent
      include MongoPercolator::Node
      class Op < MongoPercolator::Operation
        declare_parent :par, :polymorphic => true
        depends_on 'par.common'
        emit do 
          self.common_copy = "#{input 'par.common'} copy"
        end
      end
      operation :op
      key :common_copy, String
    end
  end

  before :each do
    PolymorphicParentA.remove
    PolymorphicParentB.remove
    NodeWithPolymorphicParent.remove
    MongoPercolator::Operation.remove
    @parA = PolymorphicParentA.create! :common => "I'm an A"
    @parB = PolymorphicParentB.create! :common => "Whachu looking at!"
  end

  it "instantiate the parent of the correct class (A)" do
    node = NodeWithPolymorphicParent.new
    node.create_op :par => @parA
    node.save.should be_true
    MongoPercolator.percolate
    node.reload
    node.common_copy.should == "I'm an A copy"
    node2 = NodeWithPolymorphicParent.first
    node2.op.par.should be_kind_of(PolymorphicParentA)
  end

  it "instantiate the parent of the correct class (B)" do
    node = NodeWithPolymorphicParent.new
    node.create_op :par => @parB
    node.save.should be_true
    MongoPercolator.percolate
    node.reload
    node.common_copy.should == "Whachu looking at! copy"
    node2 = NodeWithPolymorphicParent.first
    node2.op.par.should be_kind_of(PolymorphicParentB)
  end

  it "can replace the parent and get an object of the other type" do
    node = NodeWithPolymorphicParent.new
    node.create_op :par => @parA
    node.save.should be_true
    node2 = NodeWithPolymorphicParent.first
    node2.op.par.should be_kind_of(PolymorphicParentA)
    node.op.par = @parB
    node.op.save.should be_true
    node2 = NodeWithPolymorphicParent.first
    node2.op.par.should be_kind_of(PolymorphicParentB)
  end

  it "raises an error if polymorphic is used with a plural parent list" do
    expect {
      class NodeWithPolymorphicParents
        include MongoPercolator::Node
        class Op < MongoPercolator::Operation
          declare_parents :pars, :polymorphic => true
          emit {}
        end
        operation :op
      end
    }.to raise_error(ArgumentError, /polymorphic not allowed/)
  end
end

# END
