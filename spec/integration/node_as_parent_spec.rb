require 'spec_helper'

describe "Operations that depend on their node" do
  before :all do
    class NodeWithOpWatchingNode
      include MongoPercolator::Node

      key :op_depends_on_this, String
      key :not_depended_on, String
      key :result, String

      class OpWatchingNode < MongoPercolator::Operation
        declare_parent :own_node, :class => NodeWithOpWatchingNode 
        depends_on 'own_node.op_depends_on_this'
        emit do
          self.result = "Result: #{input 'own_node.op_depends_on_this'}"
        end
      end
      operation :op_watching_node
    end
  end

  before :each do
    clean_db
    @op = NodeWithOpWatchingNode::OpWatchingNode.new
    @node = NodeWithOpWatchingNode.new :op_watching_node => @op,
      :not_depended_on => "not a dependency",
      :op_depends_on_this => "is a dependency"
    @op.own_node = @node
    @op.save!
    @node.save!
  end

  it "can percolate initially" do
    NodeWithOpWatchingNode::OpWatchingNode.first.stale?.should be_true
    n = NodeWithOpWatchingNode.first
    n.result.should be_nil
    n.not_depended_on.should == "not a dependency"
    n.op_depends_on_this.should == "is a dependency"
    MongoPercolator.percolate
    n.reload
    n.result.should == "Result: is a dependency"
  end

  it "is marked as stale when the depended on property changes" do
    MongoPercolator.percolate
    n = NodeWithOpWatchingNode.first
    n.op_depends_on_this = "yes it does"
    n.save.should be_true
    NodeWithOpWatchingNode::OpWatchingNode.first.stale?.should be_true
    MongoPercolator.percolate
    n.reload
    n.result.should == "Result: yes it does"
  end

  it "is not marked as stale when a non-dependency changes" do
    MongoPercolator.percolate
    NodeWithOpWatchingNode::OpWatchingNode.first.stale?.should be_false
    n = NodeWithOpWatchingNode.first
    n.not_depended_on = "nope"
    n.save.should be_true
    NodeWithOpWatchingNode::OpWatchingNode.first.stale?.should be_false
  end
end

# END
