require 'spec_helper'

describe "Node exports integration" do
  before :all do
    class NodeExportsIntegration1
      include MongoPercolator::Node
      key :hidden, String
      key :visible, String
      export 'visible'
    end

    class NodeExportsIntegration1Decendant
      include MongoPercolator::Node
      class Op < MongoPercolator::Operation
        emit do
          self.visible_copy = input 'par.visible'
        end
        declare_parent :par, :class => NodeExportsIntegration1
        depends_on 'par.visible'
      end
      key :visible_copy, String
      operation :op
    end
  end

  before :each do
    NodeExportsIntegration1.remove
    NodeExportsIntegration1Decendant.remove
    MongoPercolator::Operation.remove
    @parent = NodeExportsIntegration1.create! :hidden => "secret", 
      :visible => "public"
    @op = NodeExportsIntegration1Decendant::Op.new :par => @parent
    @child = NodeExportsIntegration1Decendant.create! :op => @op
    @child.op.perform!
    @child.reload
  end

  it "starts off with the initial value" do
    @child.visible_copy.should == 'public'
  end

  it "gets percolated to include visible" do
    @parent.visible = "open"
    @parent.save.should be_true
    @op.reload
    @op.stale?.should be_true
    MongoPercolator.percolate
    @child.reload
    @child.visible_copy.should == "open"
  end

  it "is not percolated when hidden is changed" do
    @parent.hidden = "closed"
    @parent.save.should be_true
    @op.reload
    @op.stale?.should be_false
  end
end

# END
