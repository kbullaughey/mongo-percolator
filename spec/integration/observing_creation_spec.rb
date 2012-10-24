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

  it "destroys the observer after it's fired" do
    ClassObservedForCreation.create! :name => "Beaker"
    ObservingCreationOfSomething.first.should_not be_nil
    MongoPercolator.percolate
    ObservingCreationOfSomething.first.should be_nil
  end

  it "destroys the observer when the node is deleted" do
    observed = ClassObservedForCreation.create! :name => "Oscar"
    ObservingCreationOfSomething.first.should_not be_nil
    observed.destroy
    ObservingCreationOfSomething.first.should be_nil
  end
end

# END
