require 'spec_helper'

shared_examples "observing creation of a class" do
  it "observes the creation of an instance of ClassObservedForCreation" do
    ClassObservedForCreation.create! :name => "Big Bird"
    expect(EffectOfObserver.count).to eq(0)
    MongoPercolator.percolate
    effect = EffectOfObserver.first
    expect(effect).to_not be_nil
     expect(effect.result).to eq("who: Big Bird")
  end

  it "destroys the observer after it's fired" do
    ClassObservedForCreation.create! :name => "Beaker"
    expect(@observer_class.first).to_not be_nil
    MongoPercolator.percolate
    expect(@observer_class.first).to be_nil
  end

  it "destroys the observer when the node is deleted" do
    observed = ClassObservedForCreation.create! :name => "Oscar"
    expect(@observer_class.first).to_not be_nil
    observed.destroy
    expect(@observer_class.first).to be_nil
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
