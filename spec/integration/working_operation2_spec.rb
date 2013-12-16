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
        declare_parents :sum_terms
        depends_on 'sum_terms[].value'

        emit do
          self.sum = inputs('sum_terms[].value').sum
        end
      end
      include MongoPercolator::Node

      operation :compute, ComputeSum
      key :sum, Float, :default => 0
    end

    # Set up another node class
    class SummationWithStringParents
      class ComputeSum < MongoPercolator::Operation
        declare_parents 'sum_terms'
        depends_on 'sum_terms[].value'

        emit do
          self.sum = inputs('sum_terms[].value').sum
        end
      end
      include MongoPercolator::Node

      operation :compute, ComputeSum
      key :sum, Float, :default => 0
    end
  end

  before :each do
    clean_db
  end

  describe "Summation" do
    before :each do
      @node = Summation.new :compute => Summation::ComputeSum.new
    end

    it "starts off zero" do
      @node.sum.should == 0
    end

    it "can be initially computed asynchronously" do
      @node.compute.sum_terms = [SumTerm.new(:value => 0.1), SumTerm.new(:value => 0.2)]
      @node.compute.save.should be_true
      @node.save.should be_true
      MongoPercolator.percolate.operations.should == 1
      @node.reload
      @node.sum.round(1).should == 0.3
    end

    it "can find its node when saved" do
      @node.save.should be_true
      @node.compute.save.should be_true
      op = Summation::ComputeSum.find(@node.compute.id)
      op.node.should_not be_nil
    end

    context "Two initial terms" do
      before :each do
        @node.compute.sum_terms = [SumTerm.new(:value => 0.5), SumTerm.new(:value => 0.5)]
        @node.compute.perform!
        @node.reload
      end

      it "can compute a sum" do
        @node.sum.should == 1.0
      end
  
      it "is not marked as old if nothing has changed when saved" do
        @node.compute.stale?.should be_false
        @node.compute.save.should be_true
        @node.reload
        @node.compute.stale?.should be_false
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
        @node.compute.stale?.should be_true
        MongoPercolator.percolate
        @node.reload
        @node.sum.should == 4.49
      end

      it "calls recompute if a value changes" do
        terms = @node.compute.sum_terms
        terms[0].value = 4.99
        terms[0].save.should be_true
        MongoPercolator.percolate
        @node.reload
        @node.sum.should == 5.49
      end

      it "recomputes when propagating and giving the diff a modified object" do
        terms = @node.compute.sum_terms
        term_copy = terms[0].to_mongo
        # This set circumvents percolation
        terms[0].set :value => 6.99
        # Propagation doesn't cause recomputation becuase nothing looks changed.
        terms[0].reload
        terms[0].propagate
        MongoPercolator.percolate
        @node.reload
        @node.sum.should == 1.0
        terms[0].propagate :against => term_copy
        MongoPercolator.percolate
        @node.reload
        @node.sum.should == 7.49
      end

      it "calls perform if a parent is destroyed" do
        @node.sum.should == 1.0
        terms = @node.compute.sum_terms
        terms.first.destroy
        MongoPercolator.percolate
        @node.reload
        @node.sum.should == 0.5
      end

      pending "Check what happens when a singleton parent is removed (#{__FILE__})"

      it "does not call perform if an ignored value changes" do
        terms = @node.compute.sum_terms
        terms[0].ignored = "I changed"
        terms[0].save.should be_true
        MongoPercolator.percolate.operations.should == 0
      end
    end
  end

  describe "SummationWithStringParents" do
    before :each do
      @node = SummationWithStringParents.new :compute => SummationWithStringParents::ComputeSum.new
    end

    it "starts off zero" do
      @node.sum.should == 0
    end

    it "can be initially computed asynchronously" do
      @node.compute.sum_terms = [SumTerm.new(:value => 0.1), SumTerm.new(:value => 0.2)]
      @node.compute.save.should be_true
      @node.save.should be_true
      MongoPercolator.percolate.operations.should == 1
      @node.reload
      @node.sum.round(1).should == 0.3
    end

    context "Two initial terms" do
      before :each do
        @node.compute.sum_terms = [SumTerm.new(:value => 0.5), SumTerm.new(:value => 0.5)]
        @node.compute.perform!
        @node.reload
      end

      it "can compute a sum" do
        @node.sum.should == 1.0
      end
    end
  end
end
