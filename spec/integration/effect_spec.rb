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
    clean_db
  end

  it "can be activated asynchronously" do
    effect = HasEffect.create!(:activate => HasEffect::Activate.new)
    expect(effect.active).to be false
    MongoPercolator.percolate
    effect.reload
    expect(effect.active).to be true
  end
end

# END
