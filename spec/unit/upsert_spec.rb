require 'spec_helper'

describe "Sci Hacks" do
  before :all do
    class SciHackTest
      include MongoPercolator::Node
      key :x, Integer, :default => 0
      key :y, Integer
      key :name, String
    end
    class SciHackTest2 < SciHackTest
      key :z, Integer
    end
  end

  before :each do
    clean_db
  end

  describe "upsert" do
    it "Can create a new document with the proper type" do
      SciHackTest2.where(:name => "Bob").upsert :$set => {:x => 33}, 
        :$inc => {:z => 88, :y => 9}
      doc = SciHackTest2.first
       expect(doc.name).to eq("Bob")
      expect(doc.x).to eq(33)
      expect(doc.y).to eq(9)
      expect(doc.z).to eq(88)
    end
  
    it "Can create a new document without sci" do
      SciHackTest.where(:name => "Bob").upsert :$set => {:x => 33}, 
        :$inc => {:y => 9}
      doc = SciHackTest.first
      expect(doc).to be_a(SciHackTest)
      expect(doc.name).to eq("Bob")
      expect(doc.x).to eq(33)
      expect(doc.y).to eq(9)
    end

    it "retuns the node from the upsert" do
      doc = SciHackTest.where(:name => "Major Major").upsert :$set => {:x => 22}
      expect(SciHackTest.count).to eq(1)
       expect(doc.id).to eq(SciHackTest.first.id)
    end
  end
end
