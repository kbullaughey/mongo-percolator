require 'spec_helper'

describe "Using an Operation for an asynchronous effect" do
  before :all do
    # Set up a node class
    class HasEffect
      # An operation with no parents must be manually marked as old, this
      # provides a means to execute code asynchronously
      class Activate < MongoPercolator::Operation
        emit do
          self.active = true
        end
      end
      include MongoPercolator::Node

      operation :activate
      key :active, Boolean, :default => false
    end
  end

  before :each do
    MongoPercolator::Operation.remove
    HasEffect.remove
  end

  it "can be activated asynchronously" do
    effect = HasEffect.create!(:activate => HasEffect::Activate.new)
    effect.active.should be_false
    MongoPercolator.percolate
    effect.reload
    effect.active.should be_true
  end
end

# END
