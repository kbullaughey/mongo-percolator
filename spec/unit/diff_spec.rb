require 'spec_helper'

describe MongoPercolator::Addressable::Diff do
  before :all do
    ::MP = MongoPercolator unless Object.const_defined? :MP

    class Queen
      include MongoMapper::EmbeddedDocument
      key :weight, String
    end

    class Hive
      include MongoMapper::Document
      one :queen
      key :bee_census, Integer
    end

    # A class that acts like a document but is not itself a document.
    class Nest
      attr_accessor :queen, :species
    end
  end

  before :each do
    clean_db
  end

  context "a mongoable, but non-persisted object" do
    before :each do
      @nest = Nest.new
      @nest.queen = "sue"
      @nest.species = "termite"
    end

    it "knows that when compared against itself it hasn't changed" do
      diff = MP::Addressable::Diff.new @nest, @nest
      expect(diff.changed?(%w(queen species))).to be false
    end

    it "knows when it has changed" do
      old = @nest.dup
      @nest.queen = "bob"
      diff = MP::Addressable::Diff.new @nest, old
      expect(diff.changed?('queen')).to be true
      expect(diff.changed?('species')).to be false
    end
  end

  context "an unpersisted object" do
    before :each do
      @hive = Hive.new :bee_census => 1_000_000
      @diff = MP::Addressable::Diff.new @hive
    end

    it "was able to initialize the diff" do
      expect(@diff).to be_kind_of(MP::Addressable::Diff)
    end

    it "knows the object is not persisted" do
      expect(@diff.persisted?).to be false
    end

    it "knows non-existant addresses of an unpersisted object haven't changed" do
      expect(@diff.changed?('not_a_real_address')).to be false
    end

    it "knows the object as a whole has changed" do
      expect(@diff.changed?(%w(queen.weight bee_census))).to be true
    end
  end

  context "a persisted object" do
    before :each do
      @hive = Hive.new :bee_census => 1_000_000
      @hive.save!
      @diff = MP::Addressable::Diff.new @hive
    end

    it "knows the object is persisted" do
      expect(@diff.persisted?).to be true
    end

    it "knows that the local key hasn't changed" do
      expect(@diff.changed?('bee_census')).to be false
    end

    it "knows a non-existant property hasn't changed" do
      expect(@diff.changed?('oogabooga')).to be false
    end

    it "knows that existant, but unset assocaitions haven't changed" do
      expect(@diff.changed?('queen')).to be false
    end

    it "can detect a change in the first-level key" do
      @hive.bee_census = 2_000_000
      @diff = MP::Addressable::Diff.new @hive
      expect(@diff.changed?('bee_census')).to be true
    end

    it "can detect a newly set embedded association" do
      @hive.queen = Queen.new
      @diff = MP::Addressable::Diff.new @hive
      expect(@diff.changed?('queen')).to be true
    end

    it "sees a nil on a new association as the same as an absent association" do
      @hive.queen = Queen.new
      @diff = MP::Addressable::Diff.new @hive
      expect(@diff.changed?('queen.weight')).to be false
    end

    it "can detect a new value in a newly-added assocaition" do
      @hive.queen = Queen.new :weight => '2g'
      @diff = MP::Addressable::Diff.new @hive
      expect(@diff.changed?('queen.weight')).to be true
    end

    it "knows an inner property hasn't changed if it hasn't" do
      @hive.queen = Queen.new :weight => '2g'
      @hive.save!
      @diff = MP::Addressable::Diff.new @hive
      expect(@diff.changed?('queen.weight')).to be false
    end

    it "knows a value hasn't changed, even if the association was replaced" do
      @hive.queen = Queen.new :weight => '2g'
      @hive.save!
      original_id = @hive.queen.id
      @hive.queen = Queen.new :weight => '2g'
      new_id = @hive.queen.id
      @diff = MP::Addressable::Diff.new @hive
      expect(@diff.changed?('queen.weight')).to be false
       expect(original_id).to_not eq(new_id)
    end
  end
end

# END
