require 'spec_helper'

describe "MongoPercolator::Addressable integration" do
  before :all do
    ::MP = MongoPercolator unless Object.const_defined? :MP
    class Purpose
      include MongoMapper::EmbeddedDocument
      include MP::Addressable

      key :summary, String
    end

    class Life
      include MongoMapper::Document
      include MP::Addressable

      one :purpose
      key :span, Integer, :default => 100.years
      key :name, String
    end
  end

  before :each do
    Life.remove
  end

  describe "changed?" do
    before :each do
      @life = Life.new
    end

    context "unpersisted" do
      it "knows an unpersisted object has changed" do
        @life.diff.changed?('name').should be_true
      end
    end

    context "persisted" do
      before :each do
        @life.save!
        @fake_diff = double(:changed? => true)
      end
  
      it "doesn't cache a diff by default" do
        MP::Addressable::Diff.stub(:new).and_return(@fake_diff)
        MP::Addressable::Diff.should_receive(:new).exactly(2).times
        @life.diff.changed?('name')
        @life.diff.changed?('span')
      end
  
      it "caches a diff if requested not to" do
        MP::Addressable::Diff.stub(:new).and_return(@fake_diff)
        MP::Addressable::Diff.should_receive(:new).exactly(1).times
        @life.diff.changed?('name')
        @life.diff(:use_cached => true).changed?('span')
      end
  
      it "knows a modified first-level propery has changed" do
        @life.diff.changed?('name').should be_false
        @life.name = "Qin Shi Huang"
        @life.diff.changed?('name').should be_true
      end
  
      it "knows a replaced association has changed" do
        @life.name = 'Qin Shi Huang'
        @life.save!
        @life.purpose = Purpose.new :summary => "Become Emperor"
        @life.diff.changed?('purpose.summary').should be_true
      end
    end
  end
end
