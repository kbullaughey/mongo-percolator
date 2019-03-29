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
    clean_db
    @parent = NodeExportsIntegration1.create! :hidden => "secret", 
      :visible => "public"
    @op = NodeExportsIntegration1Decendant::Op.new :par => @parent
    @child = NodeExportsIntegration1Decendant.create! :op => @op
    @child.op.perform!
    @child.reload
  end

  it "starts off with the initial value" do
     expect(@child.visible_copy).to eq('public')
  end

  it "gets percolated to include visible" do
    @parent.visible = "open"
    expect(@parent.save).to be true
    @op.reload
    expect(@op.stale?).to be true
    MongoPercolator.percolate
    @child.reload
     expect(@child.visible_copy).to eq("open")
  end

  it "is not percolated when hidden is changed" do
    @parent.hidden = "closed"
    expect(@parent.save).to be true
    @op.reload
    expect(@op.stale?).to be false
  end
end

# END
