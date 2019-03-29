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
      key :op_data, String
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

  before(:each) { clean_db }

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
       expect(c).to eq(blah_class)
    end
  
    it "signularizes if not requested not to" do
      blah_class = Class
      stub_const("Blah", blah_class)
      c = RealOpUnfrozen.guess_class :blahs, {}
       expect(c).to eq(blah_class)
    end
  
    it "adds the reader to the parent_labels set" do
      goop_class = Class
      stub_const("Goop", goop_class)
      c = RealOpUnfrozen.declare_parent :goop
      expect(RealOpUnfrozen.parent_labels).to include(:goop)
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
    expect(node.was_run).to be false
    node.op.perform!
    node.reload
    expect(node.was_run).to be true
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
    expect(node.op).to_not be_nil
    expect(node.was_run).to be false
    node.op.perform!
    node.reload
    expect(node.was_run).to be true
  end

  it "can be put in the error state even when save doesn't work" do
    op = OpCantBeSaved.new :req => "has required field"
    expect(op.save).to be true
    expect(op.stale?).to be true
    expect(op.error?).to be false
    # manually mature the op, as ops without nodes start off 'naive'
    op.mature!
    op = OpCantBeSaved.acquire :_id => op.id
    expect(op).to_not be_nil
    op.req = nil
    expect(op.save).to be false
    op.choke!
    op.reload
    expect(op.error?).to be true
  end

  it "can save a property to nil" do
    @a = AnimalsUnitTest.new(:wild => 'fugu')
    @op = RealOpUnit.new :animals => @a, op_data: 'yummy'
    @op.save!
    expect(@op.op_data).to eq('yummy')
    @op.op_data = nil
    @op.save!
    @op.reload
    expect(@op.op_data).to be_nil
    @op.op_data = 'yuck'
    @op.save!
    @op.reload
    expect(@op.op_data).to eq('yuck')
  end

  it "doesn't overwrite state variables in save" do
    @a = AnimalsUnitTest.new(:wild => 'fugu')
    @op = RealOpUnit.new :animals => @a
    @op.save!
    @a.save!
    @op.reload
    expect(@op).to be_persisted
    expect(@op.state).to eq("naive")
    expect(@op.stale).to eq(true)
    @op.op_data = 'yummy'
    @op.save!
    @op.reload
    expect(@op.op_data).to eq('yummy')
    expect(@op.state).to eq("naive")
    expect(@op.stale).to be(true)
  end

  it "raises an error when percolating an operation without a node" do
    op = OpCantBeSaved.new :req => "has required field"
    expect(op.save).to be true
    expect {
      op.perform!
    }.to raise_error(MongoPercolator::MissingData, /node/)
  end

  pending "Check that perform! fails if the operation is not held"

  context "has an obsolete parent and normal parent" do
    before :each do
      @a = AnimalsUnitTest.new(:wild => 'fugu')
      @op = RealOpUnit.new :animals => @a
      expect(@op.save).to be true
      @raw_doc = RealOpUnit.collection.find_one
       expect(@raw_doc['parents']['ids'].first).to eq(@op.animals.id)
      @raw_doc['parents']['ids'].push BSON::ObjectId.new
      @raw_doc['parents']['meta']['old_parent'] = 1
      RealOpUnit.collection.save(@raw_doc, {})
    end

    it "gracefully handles obsolete parents" do
      op2 = RealOpUnit.first
       expect(op2.animals.id).to eq(@a.id)
      expect { op2.old_parent }.to raise_error(NoMethodError)
    end

    it "can remove the old parent" do
      op2 = RealOpUnit.first
      op2.parents.remove 'old_parent'
      reinstantiated = MongoPercolator::ParentMeta.from_mongo op2.parents.to_mongo
       expect(reinstantiated.parents.keys).to eq(["animals"])
    end
  end

  it "gracefully handles an obsolete parent when it has no parents" do
    @op = RealOpUnit.new
    expect(@op.save).to be true
    @raw_doc = RealOpUnit.collection.find_one
    @raw_doc['parents'] = {}
    @raw_doc['parents']['ids'] = [BSON::ObjectId.new]
    @raw_doc['parents']['meta'] = {'old_parent' => 1}
    RealOpUnit.collection.save(@raw_doc, {})
    op2 = RealOpUnit.first
    expect(op2.animals).to be_nil
  end

  describe "RealOpUnit" do
    it "can be finalized" do
      expect { RealOpUnit.finalize }.to_not raise_error
    end

    it "can doesn't need to look stale upon creation" do
      op = RealOpUnit.new
      op.animals_id = "a"
      op.fresh!
      expect(op.composition_changed?).to be true
      expect(op.stale?).to be false
    end

    it "can doesn't need to look stale upon creation" do
      op = RealOpUnit.new :stale => false
      op.animals_id = "a"
      expect(op.composition_changed?).to be true
      expect(op.stale?).to be false
    end

    it "responds to the parent readers" do
      op = RealOpUnit.new
      expect(op).to respond_to(:animals)
      expect(op).to respond_to(:animals_id)
      expect(op).to respond_to(:locations_unit_tests)
      expect(op).to respond_to(:locations_unit_test_ids)
    end

    it "responds to the parent writers" do
      op = RealOpUnit.new
      expect(op).to respond_to(:animals=)
      expect(op).to respond_to(:animals_id=)
      expect(op).to respond_to(:locations_unit_tests=)
      expect(op).to respond_to(:locations_unit_test_ids=)
    end

    it "cannot assign directly to parents" do
      op = RealOpUnit.new :parents => MongoPercolator::ParentMeta.new
      expect(op.parents).to be_nil
    end

    it "knows about the parent labels" do
      expect(RealOpUnit.parent_labels).to include(:animals)
      expect(RealOpUnit.parent_labels).to include(:locations_unit_tests)
    end

    it "can get an empty list of parents" do
      op = RealOpUnit.new
       expect(op.locations_unit_tests).to eq([])
    end

    it "can add parent ids to a plural label" do
      op = RealOpUnit.new
      op.locations_unit_test_ids = %w(a b c)
       expect(op.locations_unit_test_ids).to eq(%w(a b c))
       expect(op.parent_ids).to eq(%w(a b c))
    end

    it "can add a parent id to a singular label" do
      op = RealOpUnit.new
      op.animals_id = "a"
       expect(op.animals_id).to eq("a")
       expect(op.parent_ids).to eq(["a"])
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
      expect(op.stale?).to be true
      op.fresh!
      expect(op.stale?).to be false
    end

    it "cannot be marked current if it's already been persisted" do
      op = RealOpUnit.new
      expect(op.save).to be true
      expect(op.stale?).to be true
      expect {
        op.fresh!
      }.to raise_error(MongoPercolator::StateError, /persisted/)
    end

    it "uses proper default sort order, obeying priorities" do
      slow = RealOpUnit.create :priority => 2
      fast = RealOpUnit.create :priority => 0
      medium = RealOpUnit.create :priority => 1
      # manually mature the op, as ops without nodes start off 'naive'
      [slow,fast,medium].each {|op| op.mature!}
      op1 = MongoPercolator::Operation.acquire
      op2 = MongoPercolator::Operation.acquire
      op3 = MongoPercolator::Operation.acquire
       expect(op1.id).to eq(fast.id)
       expect(op2.id).to eq(medium.id)
       expect(op3.id).to eq(slow.id)
    end

    it "has a priority set by default" do
      op = RealOpUnit.create
      persisted = RealOpUnit.first
       expect(op.id).to eq(persisted.id)
      expect(op.priority).to eq(1)
      expect(persisted.priority).to eq(1)
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
        expect(@op.save).to be true
        array = @op.locations_unit_tests
        expect(array.frozen?).to be true
        expect {
          array << LocationsUnitTest.new()
        }.to raise_error(RuntimeError)
      end

      it "can tell when a parent has been added" do
        expect(@op.save).to be true
        expect(@op.diff.changed?(@op.dependencies)).to be false
        new_loc = LocationsUnitTest.create(:country => 'taiwan')
        @op.locations_unit_test_ids << new_loc.id
        expect(@op.diff.changed?(@op.dependencies)).to be true
        expect(@op.stale?).to be true
      end

      it "should know the parent is a parent" do
        expect(@op.parent?(@p1)).to be true
        expect(@op.parent?(@p2s[0])).to be true
        expect(@op.parent?(@p2s[1])).to be true
      end

      it "should know the labels for parents" do
         expect(@op.parent_label(@p1)).to eq(:animals)
         expect(@op.parent_label(@p2s[0])).to eq(:locations_unit_tests)
         expect(@op.parent_label(@p2s[1])).to eq(:locations_unit_tests)
      end

      it "can gather the data for the operation" do
        data = @op.gather
        expect(data).to be_kind_of(Hash)
         expect(data['animals.farm'].first).to eq(["pig"])
         expect(data['animals.wild'].first).to eq(["sloth", "binturong"])
        expect(data['locations_unit_tests[].country']).to be_kind_of(Array)
         expect(data['locations_unit_tests[].country']).to eq(%w(france russia))
      end

    end
  end
end

# END
