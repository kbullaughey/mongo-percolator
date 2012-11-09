require 'spec_helper'

describe "Operation integration" do
  it "raises an error if a dependency hasn't been defined (singular)" do
    class NodeWithInvalidOp2
      include MongoPercolator::Node
      class InvalidOp2 < MongoPercolator::Operation
        emit do
          input 'blah'
        end
      end
      operation :invalid_op2
    end
    node = NodeWithInvalidOp2.new :invalid_op2 => NodeWithInvalidOp2::InvalidOp2.new
    expect {
      node.invalid_op2.recompute(node)
    }.to raise_error(ArgumentError, /Invalid address/)
  end

  it "raises an error if a dependency hasn't been defined (plural)" do
    class NodeWithInvalidOp3
      include MongoPercolator::Node
      class InvalidOp3 < MongoPercolator::Operation
        emit do
          inputs 'blah'
        end
      end
      operation :invalid_op3
    end
    node = NodeWithInvalidOp3.new :invalid_op3 => NodeWithInvalidOp3::InvalidOp3.new
    expect {
      node.invalid_op3.recompute(node)
    }.to raise_error(ArgumentError, /Invalid address/)
  end
end

# END
