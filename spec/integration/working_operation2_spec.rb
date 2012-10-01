require 'spec_helper'

# Here I test a node with a variable number of parents
describe "MongoPercolator Node & Operation integration (2)" do
  before :all do
    # This will serve as the parent class
    class SumTerm
      include MongoPercolator::Node
      key :value, Float
      key :ignored, String
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

    it "starts off zero" do
      @node.sum.should == 0
    end

    context "Two initial terms" do
      before :each do
        @node.compute.sum_terms = [SumTerm.new(:value => 0.5), SumTerm.new(:value => 0.5)]
        @node.compute.recompute!
        @node.reload
      end

      it "can compute a sum" do
        @node.sum.should == 1.0
      end
  
      it "is not marked as old if nothing has changed when saved" do
        @node.compute._old.should be_false
        @node.compute.save.should be_true
        @node.reload
        @node.compute._old.should be_false
      end
  
      it "is updated when terms are added" do
        new_term = SumTerm.create(:value => 9.9)
        @node.compute.sum_term_ids << new_term.id
        @node.compute.save.should be_true
        MongoPercolator.percolate
        @node.reload
        @node.sum.should == 10.9
      end
  
      it "is updated when a term changes value" do
        terms = @node.compute.sum_terms
        terms[0].value = 3.99
        terms[0].save.should be_true
        @node.compute.reload
        @node.compute.old?.should be_true
        MongoPercolator.percolate
        @node.reload
        @node.sum.should == 4.49
      end

      it "calls recompute if a value changes" do
        @node.should_receive(:recompute)
        terms = @node.compute.sum_terms
        terms[0].value = 4.99
        terms[0].save.should be_true
        MongoPercolator.percolate
        @node.reload
        @node.sum.should == 5.49
      end

      it "does not call recompute if an ignored value changes" do
        @node.should_not_receive(:recompute)
        terms = @node.compute.sum_terms
        terms[0].ignored = "I changed"
        terms[0].save.should be_true
        MongoPercolator.percolate
      end
    end
  end
end