require 'spec_helper'

describe "Node integration" do
  before :all do
    class NodeIntegrationWithOp
      include MongoPercolator::Node
      class Op < MongoPercolator::Operation
        emit {}
      end
      operation :op
    end
  end

  before :each do
    clean_db
    @node = NodeIntegrationWithOp.new
    @node.create_op
    @node.save
  end

  it "destroys an op when node is deleted" do
    NodeIntegrationWithOp.count.should == 1
    NodeIntegrationWithOp::Op.count.should == 1
    node = NodeIntegrationWithOp.first
    node.destroy
    NodeIntegrationWithOp::Op.count.should == 0
  end

  it "doesn't destory the node when an op is deleted" do
    NodeIntegrationWithOp.count.should == 1
    NodeIntegrationWithOp::Op.count.should == 1
    op = NodeIntegrationWithOp::Op.first
    op.destroy
    NodeIntegrationWithOp.count.should == 1
  end
end

# END
