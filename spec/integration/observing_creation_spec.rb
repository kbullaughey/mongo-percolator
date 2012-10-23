require 'spec_helper'

describe "Observing creation of a class" do
  before :all do
    class ClassObservedForCreation
      include MongoPercolator::Node
      key :name, String
    end

    class ObservingCreationOfSomething < MongoPercolator::Operation
      emit do
        EffectOfObserver.create! :result => "who: #{name}"
      end
      observe_creation_of ClassObservedForCreation
    end

    class EffectOfObserver
      include MongoPercolator::Node
      key :result, String
    end
  end

  before :each do
    MongoPercolator::Operation.remove
    EffectOfObserver.remove
    ClassObservedForCreation.remove
  end

  it "observes the creation of an instance of ClassObservedForCreation" do
    ClassObservedForCreation.create! :name => "Big Bird"
    EffectOfObserver.count.should == 0
    MongoPercolator.percolate
    effect = EffectOfObserver.first
    effect.should_not be_nil
    effect.result.should == "who: Big Bird"
  end
end

# END
