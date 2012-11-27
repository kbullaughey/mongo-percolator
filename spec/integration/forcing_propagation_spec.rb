require 'spec_helper'

shared_examples "forcing propagation" do
  it "starts with child having a counter of 1" do
    @child.counter.should == 1
  end

  it "propagates if the parent has changed" do
    @mommy.mood = "dark"
    @mommy.save.should be_true
    MongoPercolator.percolate
    @child.reload
    @child.counter.should == 2
  end

  it "doesn't propagate when the parent hasn't changed" do
    @mommy.save.should be_true
    MongoPercolator.percolate
    @child.reload
    @child.counter.should == 1
  end

  it "can be forced to propagate even if parent hasn't changed" do
    @mommy.propagate :force => true
    MongoPercolator.percolate
    @child.reload
    @child.counter.should == 2
  end
end

describe "Forcing propagation" do
  before :all do
    class ParentToForcePropagation
      include MongoPercolator::Node
      key :mood, String
    end

    class NodeToForcePropagation
      include MongoPercolator::Node
      class Increment < MongoPercolator::Operation
        emit { self.counter += 1 }
        declare_parent :mommy, :class => ParentToForcePropagation
        depends_on 'mommy.mood'
      end
      key :counter, Integer, :default => 0
      operation :increment
    end

    class ParentToForcePropagationExports
      include MongoPercolator::Node
      key :mood, String
      key :real_mood, String
      export 'mood'
    end

    class NodeToForcePropagationExports
      include MongoPercolator::Node
      class Increment < MongoPercolator::Operation
        emit { self.counter += 1 }
        declare_parent :mommy, :class => ParentToForcePropagationExports
        depends_on 'mommy.mood'
        # This is not exported, so we won't be sensitive to changes in it.
        depends_on 'mommy.real_mood'
      end
      key :counter, Integer, :default => 0
      operation :increment
    end
  end

  before :each do
    MongoPercolator::Operation.remove
  end

  context "no exports" do
    before :each do
      ParentToForcePropagation.remove
      NodeToForcePropagation.remove
      @mommy = ParentToForcePropagation.create! :mood => "jovial"
      op = NodeToForcePropagation::Increment.new :mommy => @mommy
      @child = NodeToForcePropagation.create! :increment => op
      MongoPercolator.percolate
      @child.reload
    end
  
    it_behaves_like "forcing propagation"
  end

  context "has exports" do
    before :each do
      ParentToForcePropagationExports.remove
      NodeToForcePropagationExports.remove
      @mommy = ParentToForcePropagationExports.create! :mood => "jovial"
      op = NodeToForcePropagationExports::Increment.new :mommy => @mommy
      @child = NodeToForcePropagationExports.create! :increment => op
      MongoPercolator.percolate
      @child.reload
    end
  
    it_behaves_like "forcing propagation"

    it "doesn't percolate when a non-exported property changes" do
      # make sure exports are working
      @mommy.real_mood = "dark"
      @mommy.save.should be_true
      MongoPercolator.percolate
      @child.reload
      @child.counter.should == 1
    end
  end
end

# END

