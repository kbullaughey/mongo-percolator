require 'spec_helper'

# Here I test a node with a variable number of parents
describe "MongoPercolator Node & Operation integration (2)" do
  before :all do
    # This will serve as the parent class
    class SumTerm
      include MongoPercolator::Node
      key :value, Float
    end

    # Set up a node class
    class Summation
      class ComputeSum < MongoPercolator::Operation
        parents :sum_terms
        depends_on 'sum_terms'
        computes(:sum) { key :sum, Float, :default => 0 }

        emit { self.sum = inputs['sum_terms'].collect{|t| t.value}.sum }
      end
      include MongoPercolator::Node

      operation :compute, ComputeSum
    end
  end

  before :each do
    SumTerm.remove
    MongoPercolator::Operation.remove
    Summation.remove
  end

  describe "Summation" do
    before :each do
      @node = Summation.new :compute => Summation::ComputeSum.new
    end
    it "can compute a sum" do
      @node.sum.should == 0
      @node.compute.sum_terms = [SumTerm.new(:value => 1.5), SumTerm.new(:value => 0.5)]
      @node.compute.recompute!
      @node.reload
      @node.sum.should == 2.0
    end
  end
end
