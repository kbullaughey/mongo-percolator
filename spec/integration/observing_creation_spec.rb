require 'spec_helper'

shared_examples "observing creation of a class" do
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
    @observer_class.first.should_not be_nil
    MongoPercolator.percolate
    @observer_class.first.should be_nil
  end

  it "destroys the observer when the node is deleted" do
    observed = ClassObservedForCreation.create! :name => "Oscar"
    @observer_class.first.should_not be_nil
    observed.destroy
    @observer_class.first.should be_nil
  end
end

describe "Observing creation of a class" do
  before :all do
    class ClassObservedForCreation
      include MongoPercolator::Node
      key :name, String
    end

    class EffectOfObserver
      include MongoPercolator::Node
      key :result, String
    end
  end

  before :each do
    clean_db
  end

  context "using a class object" do
    before :all do
      class ObservingCreationOfSomething < MongoPercolator::Operation
        emit do
          EffectOfObserver.create! :result => "who: #{name}"
        end
        observe_creation_of ClassObservedForCreation
      end
      @observer_class = ObservingCreationOfSomething
    end
    it_behaves_like "observing creation of a class"
  end

  context "using a symbol" do
    before :all do
      class ObservingCreationOfSomething2 < MongoPercolator::Operation
        emit do
          EffectOfObserver.create! :result => "who: #{name}"
        end
        observe_creation_of :class_observed_for_creation
      end
      @observer_class = ObservingCreationOfSomething2
    end
    it_behaves_like "observing creation of a class"
  end

  context "using an underscored string" do
    before :all do
      class ObservingCreationOfSomething3 < MongoPercolator::Operation
        emit do
          EffectOfObserver.create! :result => "who: #{name}"
        end
        observe_creation_of 'class_observed_for_creation'
      end
      @observer_class = ObservingCreationOfSomething3
    end
    it_behaves_like "observing creation of a class"
  end

  context "using a camelized string" do
    before :all do
      class ObservingCreationOfSomething4 < MongoPercolator::Operation
        emit do
          EffectOfObserver.create! :result => "who: #{name}"
        end
        observe_creation_of 'ClassObservedForCreation'
      end
      @observer_class = ObservingCreationOfSomething4
    end
    it_behaves_like "observing creation of a class"
  end
end

# END
