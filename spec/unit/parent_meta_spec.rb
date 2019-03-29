require 'spec_helper'

describe MongoPercolator::ParentMeta do
  before :all do
    class ParentMetaContainer1
      include MongoMapper::Document
      key :parents, MongoPercolator::ParentMeta
    end
  end

  before :each do
    clean_db
  end

  it "starts off empth" do
     expect(subject.ids).to eq([])
  end

  it "return an empty array if a parent doesn't exist" do
     expect(subject['no parent']).to eq([])
  end

  it "raises an error if not passed a hash" do
    expect { MongoPercolator::ParentMeta.new 1 }.
      to raise_error(TypeError)
  end

  it "can set a new parent" do
    subject['new_parent'] = %w(t u v)
     expect(subject.ids).to eq(%w(t u v))
  end

  it "can test if a parent label is defined" do
    subject['new_parent'] = %w(t u v)
    expect(subject.parents.include?('new_parent')).to be true
    expect(subject.parents.include?('uncle')).to be false
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
       expect(@pm.ids).to eq(%w(a b c))
       expect(@pm['p1']).to eq(['a'])
       expect(@pm['p2']).to eq(['b', 'c'])
    end

    it "can have a parent's ids added to" do
      @pm['p1'] << 'x'
       expect(@pm['p1']).to eq(%w(a x))
       expect(@pm.ids).to eq(%w(a x b c))
    end

    it "can set a parent's ids" do
      @pm['p2'] = %w(q r s)
       expect(@pm.ids).to eq(%w(a q r s))
    end

    it "can be serialized to mongo" do
      mongo = @pm.to_mongo
       expect(mongo['ids']).to eq(%w(a b c))
       expect(mongo['meta']).to eq({'p1' => 1, 'p2' => 2})
    end

    it "can return the first parent's name" do
       expect(@pm.parent_at(0)).to eq("p1")
       expect(@pm.parent_at(1)).to eq("p2")
       expect(@pm.parent_at(2)).to eq("p2")
    end

    it "knows how many parents there are" do
      expect(@pm.length).to eq(3)
    end

    it "can be initialized with no parents of one type" do
      pm2 = MongoPercolator::ParentMeta.new :ids => [], :meta => {'p1' => 0}
       expect(pm2.ids).to eq([])
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
      expect(@pm.ids).to include('x')
      expect(@pm.ids).to include('y')
      expect(@pm.ids).to include('z')
    end

    it "cannot add a new parent type when frozen" do
      @pm.freeze
      expect { 
        @pm['newbie'] = %w(x y z)
      }.to raise_error()
    end

    it "can produce a diff" do
      old = @pm.to_mongo
      properties = %w(ids meta)
      expect(@pm.diff(:against => old).changed?(properties)).to be false
      @pm['p1'] << "v"
      expect(@pm.diff(:against => old).changed?(properties)).to be true
    end

    describe "MongoDB interaction" do
      it "can be persisted to mongo and read from mongo" do
        c = ParentMetaContainer1.new
        c.parents = @pm
        expect(c.save).to be true
        c_restored = ParentMetaContainer1.first
         expect(c_restored.parents.ids).to eq(%w(a b c))
         expect(c_restored.parents['p2']).to eq(%w(b c))
      end

      it "can be nil" do
        c = ParentMetaContainer1.new
        c.parents = nil
        expect(c.save).to be true
        c_restored = ParentMetaContainer1.first
        expect(c_restored.parents).to be_nil
      end
    end
  end
end

# END
