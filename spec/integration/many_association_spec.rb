require 'spec_helper'

describe "MongoPercolator many association (integration)" do
  before :all do
    class Dugong
      include MongoPercolator::Node
      key :name, String
    end
    class DugongHome
      include MongoMapper::EmbeddedDocument
      key :dugong_ids, :default => []
      many :dugongs, :in => :dugong_ids
    end
    class TestManyAssociation1
      include MongoPercolator::Node
      key :dugong_ids, :default => []
      many :dugongs, :in => :dugong_ids
    end
    class TestManyAssociation2
      include MongoPercolator::Node
      one :dugong_home
    end
  end

  before :each do
    MongoPercolator::Many::Copy.remove
    TestManyAssociation2.remove
    TestManyAssociation1.remove
    Dugong.remove
  end

  it "calls update_many_copy_for on save" do
    MongoPercolator::Many.should_receive(:update_many_copy_for)
    TestManyAssociation1.new.save
  end

  it "can find the path for a root-level property" do
    a = TestManyAssociation1.new
    a.save
    many_copy = MongoPercolator::Many::Copy.where(:node_id => a.id).first
    many_copy.should_not be_nil
    many_copy.node_type.should == "TestManyAssociation1"
    many_copy.path.should == "dugong_ids"
    many_copy.ids.should == []
  end

  it "can find the path for a property in an embedded document" do
  end

  it "sets the ids when there are some" do
    a = TestManyAssociation1.new
    a.dugongs << Dugong.new(:name => "Barney")
    a.dugongs << Dugong.new(:name => "Fred")
    a.save.should be_true
    many_copy = MongoPercolator::Many::Copy.where(:node_id => a.id).first
    many_copy.ids.should include(a.dugongs[0].id)
    many_copy.ids.should include(a.dugongs[1].id)
  end

  it "can find the path for a root level many association" do
    a = TestManyAssociation1.new
    a.dugongs << Dugong.new(:name => "Barney")
    a.save
    many_copy = MongoPercolator::Many::Copy.where(:node_id => a.id).first
    many_copy.ids.should include(a.dugongs.first.id)
    MongoPercolator::Many.delete_id a.dugongs.first.id
    many_copy.reload
    many_copy.ids.should_not include(a.dugongs.first.id)
    a.reload
    a.dugongs.should == []
    a.dugong_ids.should == []
  end

  it "deletes the id automatically on destroy" do
    a = TestManyAssociation1.new
    doomed_dugong = Dugong.new(:name => "Barney")
    a.dugongs << doomed_dugong
    a.save
    Dugong.find(doomed_dugong.id).should_not be_nil
    many_copy = MongoPercolator::Many::Copy.where(:node_id => a.id).first
    many_copy.ids.should include(doomed_dugong.id)
    a.dugong_ids.should include(doomed_dugong.id)
    doomed_dugong.destroy
    many_copy.reload
    a.reload
    many_copy.ids.should_not include(doomed_dugong.id)
    a.dugong_ids.should_not include(doomed_dugong.id)
  end
end

# END



