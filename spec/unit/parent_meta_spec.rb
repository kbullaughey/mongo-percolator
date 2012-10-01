require 'spec_helper'

describe MongoPercolator::ParentMeta do
  before :all do
    class ParentMetaContainer1
      include MongoMapper::Document
      key :parents, MongoPercolator::ParentMeta
    end
  end

  before :each do
    ParentMetaContainer1.remove
  end

  it "starts off empth" do
    subject.ids.should == []
  end

  it "raises a key error if a parent doesn't exist" do
    expect { subject['no parent'] }.to raise_error(KeyError)
  end

  it "raises an error if not passed a hash" do
    expect { MongoPercolator::ParentMeta.new 1 }.
      to raise_error(TypeError)
  end

  it "can set a new parent" do
    subject['new_parent'] = %w(t u v)
    subject.ids.should == %w(t u v)
  end

  it "can test if a parent label is defined" do
    subject['new_parent'] = %w(t u v)
    subject.parents.include?('new_parent').should be_true
    subject.parents.include?('uncle').should be_false
  end

  it "raises an error if meta isn't a hash" do
    expect {
      MongoPercolator::ParentMeta.new :meta => 1
    }.to raise_error(TypeError)
  end

  it "raises an error if counts aren't numbers" do
    expect {
      MongoPercolator::ParentMeta.new :ids => ['id1'], :meta => {'a' => '1'}
    }.to raise_error(TypeError, /fixnum/)
  end

  it "raises an error if ids are the wrong length" do
    expect {
      MongoPercolator::ParentMeta.new :meta => {'a' => 1}
    }.to raise_error(ArgumentError, /unexpected length/)
  end

  context "A simple ParentMeta" do
    before :each do
      @pm = MongoPercolator::ParentMeta.new :ids => %w(a b c), 
        :meta => {'p1' => 1, 'p2' => 2}
    end
  
    it "can be initialized from a hash" do
      @pm.ids.should == %w(a b c)
      @pm['p1'].should == ['a']
      @pm['p2'].should == ['b', 'c']
    end

    it "can have a parent's ids added to" do
      @pm['p1'] << 'x'
      @pm['p1'].should == %w(a x)
      @pm.ids.should == %w(a x b c)
    end

    it "can set a parent's ids" do
      @pm['p2'] = %w(q r s)
      @pm.ids.should == %w(a q r s)
    end

    it "can be serialized to mongo" do
      mongo = @pm.to_mongo
      mongo['ids'].should == %w(a b c)
      mongo['meta'].should == {'p1' => 1, 'p2' => 2}
    end

    it "can return the first parent's name" do
      @pm.parent_at(0).should == "p1"
      @pm.parent_at(1).should == "p2"
      @pm.parent_at(2).should == "p2"
    end

    it "knows how many parents there are" do
      @pm.length.should == 3
    end

    it "can be initialized with no parents of one type" do
      pm2 = MongoPercolator::ParentMeta.new :ids => [], :meta => {'p1' => 0}
      pm2.ids.should == []
    end

    it "cannot have a parent id array set to nil" do
      expect {
        @pm['p1'] = nil
      }.to raise_error(TypeError)
    end

    it "can add a first parent of a type after being frozen" do
      @pm['newbie'] = []
      @pm.freeze
      @pm['newbie'] = %w(x y z)
      @pm.ids.should include('x')
      @pm.ids.should include('y')
      @pm.ids.should include('z')
    end

    it "cannot add a new parent type when frozen" do
      @pm.freeze
      expect { 
        @pm['newbie'] = %w(x y z)
      }.to raise_error()
    end

    it "can produce a diff" do
      old = @pm.to_mongo
      @pm.diff(:against => old).changed?.should be_false
      @pm['p1'] << "v"
      @pm.diff(:against => old).changed?.should be_true
    end

    describe "MongoDB interaction" do
      it "can be persisted to mongo and read from mongo" do
        c = ParentMetaContainer1.new
        c.parents = @pm
        c.save.should be_true
        c_restored = ParentMetaContainer1.first
        c_restored.parents.ids.should == %w(a b c)
        c_restored.parents['p2'].should == %w(b c)
      end

      it "can be nil" do
        c = ParentMetaContainer1.new
        c.parents = nil
        c.save.should be_true
        c_restored = ParentMetaContainer1.first
        c_restored.parents.should be_nil
      end
    end
  end
end

# END
