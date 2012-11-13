require 'spec_helper'

describe "MongoPercolator::Operation unit" do
  before :all do
    # Set up a derived class with no computed properties
    class NoOp < MongoPercolator::Operation
    end

    class AnimalsUnitTest
      include MongoMapper::Document
      key :wild, Array
      key :farm, Array
    end

    class LocationsUnitTest
      include MongoMapper::Document
      key :country, String
    end

    # Set up a derived class with a few computed properties
    class RealOpUnit < MongoPercolator::Operation
      emit {}
      declare_parent :animals, :class => AnimalsUnitTest
      declare_parents :locations_unit_tests
      depends_on 'animals.farm'
      depends_on 'animals.wild'
      depends_on 'locations_unit_tests[].country'
    end

    # Set up another derived class that isn't inserted into a node and thus
    # remains unfrozen.
    class RealOpUnfrozen < MongoPercolator::Operation
    end

    # Set up an node & operation to test the abbreviated operation syntax
    class NodeWithAbbreviatedSyntax
      class Op < MongoPercolator::Operation
        emit { self.was_run = true }
      end
      include MongoPercolator::Node
      operation :op
      key :was_run, Boolean, :default => false
    end
    
    class OpCantBeSaved < MongoPercolator::Operation
      emit {}
      key :req, String, :required => true
    end
  end

  before :each do
    RealOpUnit.remove
    LocationsUnitTest.remove
    AnimalsUnitTest.remove
    NodeWithAbbreviatedSyntax.remove
  end

  describe "DSL is limited to subclasses" do
    it "#parent" do
      expect {
        MongoPercolator::Operation.declare_parent :blah
      }.to raise_error(RuntimeError, /subclass/)
    end

    it "#parents" do
      expect {
        MongoPercolator::Operation.declare_parents :blah
      }.to raise_error(RuntimeError, /subclass/)
    end

    it "#emit" do
      expect {
        MongoPercolator::Operation.emit
      }.to raise_error(RuntimeError, /subclass/)
    end

    it "#depends_on" do
      expect {
        MongoPercolator::Operation.depends_on :blah
      }.to raise_error(RuntimeError, /subclass/)
    end
  end

  describe "guess_class" do
    it "cannot be called on Operation" do
      expect {
        MongoPercolator::Operation.guess_class :blah, {}
      }.to raise_error(RuntimeError, /subclass/)
    end

    it "doesn't singularize if requested not to" do
      blah_class = Class
      stub_const("Blahs", blah_class)
      c = RealOpUnfrozen.guess_class :blahs, 
        :no_singularize => true
      c.should == blah_class
    end
  
    it "signularizes if not requested not to" do
      blah_class = Class
      stub_const("Blah", blah_class)
      c = RealOpUnfrozen.guess_class :blahs, {}
      c.should == blah_class
    end
  
    it "adds the reader to the parent_labels set" do
      goop_class = Class
      stub_const("Goop", goop_class)
      c = RealOpUnfrozen.guess_class(:goop, {})
      RealOpUnfrozen.parent_labels.should include(:goop)
    end
  end

  describe "NoOp" do
    it "finalize fails without emit block" do
      expect {
        NoOp.finalize
      }.to raise_error(NotImplementedError, /emit/)
    end
  end

  it "can use the abbreviated operation syntax" do
    node = NodeWithAbbreviatedSyntax.create!(:op => NodeWithAbbreviatedSyntax::Op.new)   
    node.was_run.should be_false
    node.op.perform!
    node.reload
    node.was_run.should be_true
  end

  it "raises an error if a dependency doesn't reach into a parent" do
    class InvalidOp1 < MongoPercolator::Operation
      emit {}
      declare_parent :animals, :class => AnimalsUnitTest
    end
    expect {
      InvalidOp1.depends_on 'animals'
    }.to raise_error(ArgumentError, /enter parent/)
  end

  it "can be created using the create_* convenience function" do
    node = NodeWithAbbreviatedSyntax.create
    node.create_op
    node.was_run.should be_false
    node.op.perform!
    node.reload
    node.was_run.should be_true
  end

  it "can be put in the error state even when save doesn't work" do
    op = OpCantBeSaved.new :req => "has required field"
    op.save.should be_true
    op.stale?.should be_true
    op.error?.should be_false
    op = OpCantBeSaved.fetch :_id => op.id
    op.should_not be_nil
    op.req = nil
    op.save.should be_false
    op.choke!
    op.reload
    op.error?.should be_true
  end

  pending "Check that state variables are not overwritten by save"

  it "raises an error when percolating an operation without a node" do
    op = OpCantBeSaved.new :req => "has required field"
    op.save.should be_true
    expect {
      op.perform!
    }.to raise_error(MongoPercolator::MissingData, /node/)
  end

  pending "Check that perform! fails if the operation is not held"

  describe "RealOpUnit" do
    it "can be finalized" do
      expect { RealOpUnit.finalize }.to_not raise_error
    end

    it "can doesn't need to look stale upon creation" do
      op = RealOpUnit.new
      op.animals_id = "a"
      op.fresh!
      op.composition_changed?.should be_true
      op.stale?.should be_false
    end

    it "responds to the parent readers" do
      op = RealOpUnit.new
      op.should respond_to(:animals)
      op.should respond_to(:animals_id)
      op.should respond_to(:locations_unit_tests)
      op.should respond_to(:locations_unit_test_ids)
    end

    it "responds to the parent writers" do
      op = RealOpUnit.new
      op.should respond_to(:animals=)
      op.should respond_to(:animals_id=)
      op.should respond_to(:locations_unit_tests=)
      op.should respond_to(:locations_unit_test_ids=)
    end

    it "cannot assign directly to parents" do
      op = RealOpUnit.new :parents => MongoPercolator::ParentMeta.new
      op.parents.should be_nil
    end

    it "knows about the parent labels" do
      RealOpUnit.parent_labels.should include(:animals)
      RealOpUnit.parent_labels.should include(:locations_unit_tests)
    end

    it "can get an empty list of parents" do
      op = RealOpUnit.new
      op.locations_unit_tests.should == []
    end

    it "can add parent ids to a plural label" do
      op = RealOpUnit.new
      op.locations_unit_test_ids = %w(a b c)
      op.locations_unit_test_ids.should == %w(a b c)
      op.parent_ids.should == %w(a b c)
    end

    it "can add a parent id to a singular label" do
      op = RealOpUnit.new
      op.animals_id = "a"
      op.animals_id.should == "a"
      op.parent_ids.should == ["a"]
    end

    it "cannot be recomputed when not attached to a node" do
      op = RealOpUnit.new
      op.animals_id = "a"
      expect {
        op.perform!
      }.to raise_error(MongoPercolator::MissingData, /node/)
    end

    it "can be marked current when not yet persisted" do
      op = RealOpUnit.new
      op.stale?.should be_true
      op.fresh!
      op.stale?.should be_false
    end

    it "cannot be marked current if it's already been persisted" do
      op = RealOpUnit.new
      op.save.should be_true
      op.stale?.should be_true
      expect {
        op.fresh!
      }.to raise_error(MongoPercolator::StateError, /persisted/)
    end

    context "has parents" do
      before :each do
        @p1 = AnimalsUnitTest.new(:wild => %w(sloth binturong), :farm => ["pig"])
        @p2s = [LocationsUnitTest.new(:country => 'france'), 
          LocationsUnitTest.new(:country => 'russia')]
        p2_ids = @p2s.collect{|x| x.id}
        @op = RealOpUnit.new :animals => @p1, :locations_unit_tests => @p2s
      end

      it "can't modify the array returned by the plural reader" do
        @op.save.should be_true
        array = @op.locations_unit_tests
        array.frozen?.should be_true
        expect {
          array << LocationsUnitTest.new()
        }.to raise_error(RuntimeError)
      end

      it "can tell when a parent has been added" do
        @op.save.should be_true
        @op.diff.changed?(@op.dependencies).should be_false
        new_loc = LocationsUnitTest.create(:country => 'taiwan')
        @op.locations_unit_test_ids << new_loc.id
        @op.diff.changed?(@op.dependencies).should be_true
        @op.stale?.should be_true
      end

      it "should know the parent is a parent" do
        @op.parent?(@p1).should be_true
        @op.parent?(@p2s[0]).should be_true
        @op.parent?(@p2s[1]).should be_true
      end

      it "should know the labels for parents" do
        @op.parent_label(@p1).should == :animals
        @op.parent_label(@p2s[0]).should == :locations_unit_tests
        @op.parent_label(@p2s[1]).should == :locations_unit_tests
      end

      it "can gather the data for the operation" do
        data = @op.gather
        data.should be_kind_of(Hash)
        data['animals.farm'].first.should == ["pig"]
        data['animals.wild'].first.should == ["sloth", "binturong"]
        data['locations_unit_tests[].country'].should be_kind_of(Array)
        data['locations_unit_tests[].country'].should == %w(france russia)
      end
    end
  end
end

# END
