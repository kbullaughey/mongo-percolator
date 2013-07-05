require 'spec_helper'

describe "MongoPercolator many association (integration)" do
  before :all do
    class Dugong
      include MongoPercolator::Node
      key :name, String
    end

    class DugongFamily
      include MongoPercolator::EmbeddedNode
      key :dugong_ids, Array, :default => []
      many :dugongs, :in => :dugong_ids
    end

    class DugongHome
      include MongoPercolator::EmbeddedNode
      key :dugong_ids, Array, :default => []
      many :dugongs, :in => :dugong_ids
    end

    class DugongMultiFamilyHome
      include MongoPercolator::EmbeddedNode
      many :dugong_familys
    end

    class TestManyAssociation1
      include MongoPercolator::Node
      key :dugong_ids, Array, :default => []
      many :dugongs, :in => :dugong_ids
    end

    class TestManyAssociation2
      include MongoPercolator::Node
      one :dugong_home
    end

    class TestManyAssociation3
      include MongoPercolator::Node
      many :dugong_homes
    end

    class TestManyAssociation4
      include MongoPercolator::Node
      many :dugong_multi_family_homes
    end
  end

  before :each do
    clean_db
  end

  it "calls update_many_copy_for on save" do
    MongoPercolator::Many.should_receive(:update_many_copy_for)
    TestManyAssociation1.new.save
  end

  it "can find the path for a root-level property" do
    a = TestManyAssociation1.new
    a.save
    many_copy = MongoPercolator::Many::Copy.where(:root_id => a.id).first
    many_copy.should_not be_nil
    many_copy.root_type.should == "TestManyAssociation1"
    many_copy.label.should == "dugong_ids"
    many_copy.path.should be_nil
    many_copy.ids.should == []
  end

  context "Have some Dugongs" do
    before :each do
      @marvin = Dugong.new(:name => "Marvin")
      @fred = Dugong.new(:name => "Jacob")
      @barney = Dugong.new(:name => "Barney")
    end

    it "can find the path for a property in an embedded document" do
      a = TestManyAssociation2.new
      a.build_dugong_home :dugongs => [@marvin, @fred]
      a.save
      many_copy = MongoPercolator::Many::Copy.where(:root_id => a.id).first
      many_copy.path.should == "dugong_home"
      many_copy.label.should == "dugong_ids"
      many_copy.node_id.should == a.dugong_home.id
    end
  
    it "can find the path through a many association" do
      a = TestManyAssociation3.new
      a.dugong_homes = [
        DugongHome.new(:dugongs => [@barney]),
        DugongHome.new(:dugongs => [@marvin, @fred]),
      ]
      a.save
      many_copies = MongoPercolator::Many::Copy.where(:root_id => a.id).all
      many_copies.length.should == 2
      paths = many_copies.collect {|copy| copy.path}
      paths.should include("dugong_homes[#{a.dugong_homes[0].id}]")
      paths.should include("dugong_homes[#{a.dugong_homes[1].id}]")
      many_copies.each {|copy| copy.label.should == "dugong_ids"}
    end
  
    it "reflects swapping dugongs" do
      a = TestManyAssociation3.new
      barneys_home = DugongHome.new :dugongs => [@barney]
      marvins_home = DugongHome.new :dugongs => [@marvin]
      a.dugong_homes = [barneys_home, marvins_home]
      a.save
      many_copies = MongoPercolator::Many::Copy.where(:root_id => a.id).all
      barneys_copy = many_copies.select {|copy| copy.node_id == barneys_home.id}.first
      marvins_copy = many_copies.select {|copy| copy.node_id == marvins_home.id}.first
      barneys_copy.should_not be_nil
      marvins_copy.should_not be_nil
      barneys_copy.ids.should == [@barney.id]
      marvins_copy.ids.should == [@marvin.id]
      barneys_copy.full_path.should == "dugong_homes[#{barneys_home.id}].dugong_ids"
      marvins_copy.full_path.should == "dugong_homes[#{marvins_home.id}].dugong_ids"
      a.dugong_homes[0].dugongs = [@marvin]
      a.dugong_homes[1].dugongs = [@barney]
      a.save
      barneys_copy.reload
      marvins_copy.reload
      barneys_copy.ids.should == [@marvin.id]
      marvins_copy.ids.should == [@barney.id]
    end

    context "multi-layer example" do
      before :each do
        # TestManyAssociation > DugongMultiFamilyHomes > DugongFamilies > Dugongs
        @a = TestManyAssociation4.new
        @barneys_family = DugongFamily.new :dugongs => [@barney]
        @marvins_family = DugongFamily.new :dugongs => [@marvin]
        @freds_family = DugongFamily.new :dugongs => [@fred]
        @barney_and_freds_home = DugongMultiFamilyHome.new(
          :dugong_familys => [@barneys_family, @freds_family])
        @marvins_home = DugongMultiFamilyHome.new :dugong_familys => [@marvins_family]
        @a.dugong_multi_family_homes = [@barney_and_freds_home, @marvins_home]
        @a.save
      end

      it "reflects changing the dugong home" do
        # Check the path to barney
        many_copy = MongoPercolator::Many::Copy.
          where(:node_id => @barneys_family.id).first
        many_copy.should_not be_nil
        many_copy.full_path.should == 
          "dugong_multi_family_homes[#{@barney_and_freds_home.id}]."+
          "dugong_familys[#{@barneys_family.id}].dugong_ids"
        many_copy.ids.should == [@barney.id]
  
        # Swap barneys family into marvin's home and set this as the dugong home
        @a.dugong_multi_family_homes[0].dugong_familys = [@freds_family]
        @a.dugong_multi_family_homes[1].dugong_familys = 
          [@marvins_family, @barneys_family]
        @a.save
  
        # It should use the same many_copy, because the node_id and label hasn't
        # changed.
        many_copy.reload
        many_copy.full_path.should ==
          "dugong_multi_family_homes[#{@a.dugong_multi_family_homes[1].id}]."+
          "dugong_familys[#{@barneys_family.id}].dugong_ids"
        many_copy.ids.should == [@barney.id]
        many_copy.root_id.should == @a.id
        many_copy.root_type.should == @a.class.to_s
      end

      it "removes the id when destroyed" do
        @barney.destroy
        @a.reload
        home = @a.dugong_multi_family_homes.
          select{|h| h.id == @barney_and_freds_home.id}.first
        family = home.dugong_familys.
          select{|f| f.id == @barneys_family.id}.first
        family.dugong_ids.should == []
      end

      it "removes the many copy when root is destroyed" do
        MongoPercolator::Many::Copy.where(:root_id => @a.id).count.should > 0
        @a.destroy
        MongoPercolator::Many::Copy.where(:root_id => @a.id).count.should == 0
      end
    end

    it "sets the ids when there are some" do
      a = TestManyAssociation1.new
      a.dugongs << @marvin
      a.dugongs << @fred
      a.save.should be_true
      many_copy = MongoPercolator::Many::Copy.where(:root_id => a.id).first
      many_copy.ids.should include(a.dugongs[0].id)
      many_copy.ids.should include(a.dugongs[1].id)
    end
  
    it "can find the path for a root level many association" do
      a = TestManyAssociation1.new
      a.dugongs << @marvin
      a.save
      many_copy = MongoPercolator::Many::Copy.where(:root_id => a.id).first
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
      doomed_dugong = @marvin
      a.dugongs << doomed_dugong
      a.save
      Dugong.find(doomed_dugong.id).should_not be_nil
      many_copy = MongoPercolator::Many::Copy.where(:root_id => a.id).first
      many_copy.ids.should include(doomed_dugong.id)
      a.dugong_ids.should include(doomed_dugong.id)
      doomed_dugong.destroy
      many_copy.reload
      a.reload
      many_copy.ids.should_not include(doomed_dugong.id)
      a.dugong_ids.should_not include(doomed_dugong.id)
    end
  end
end

# END



