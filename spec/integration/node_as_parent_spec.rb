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
    expect(NodeWithOpWatchingNode::OpWatchingNode.first.stale?).to be true
    n = NodeWithOpWatchingNode.first
    expect(n.result).to be_nil
     expect(n.not_depended_on).to eq("not a dependency")
     expect(n.op_depends_on_this).to eq("is a dependency")
    MongoPercolator.percolate
    n.reload
     expect(n.result).to eq("Result: is a dependency")
  end

  it "is marked as stale when the depended on property changes" do
    MongoPercolator.percolate
    n = NodeWithOpWatchingNode.first
    n.op_depends_on_this = "yes it does"
    expect(n.save).to be true
    expect(NodeWithOpWatchingNode::OpWatchingNode.first.stale?).to be true
    MongoPercolator.percolate
    n.reload
     expect(n.result).to eq("Result: yes it does")
  end

  it "is not marked as stale when a non-dependency changes" do
    MongoPercolator.percolate
    expect(NodeWithOpWatchingNode::OpWatchingNode.first.stale?).to be false
    n = NodeWithOpWatchingNode.first
    n.not_depended_on = "nope"
    expect(n.save).to be true
    expect(NodeWithOpWatchingNode::OpWatchingNode.first.stale?).to be false
  end
end

# END
