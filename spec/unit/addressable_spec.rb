require 'spec_helper'

describe "MongoPercolator::Addressable unit" do
  before :all do
    MP = MongoPercolator
    class Layer1
      include MP::Addressable
      class Layer2
        class Layer3
          def boom
            "Ouch!"
          end
        end
        def bam
          Layer3.new
        end
      end
      def bing
        Layer2.new
      end
      def bada
        {:bing => {'bada' => {'bam' => {'bada' => {'boom' => 'Ouch!!!'}}}}, :nothing => nil}
      end
    end
  end

  describe "fetching" do
    it "raises an error if options is not a hash" do
      expect {
        Layer1.new.fetch('blah', "not a hash")
      }.to raise_error(ArgumentError, /expecting a hash/)
    end
  
    it "raises an error if options is not a hash in class method" do
      expect {
        MP::Addressable.fetch('blah', "not a hash")
      }.to raise_error(ArgumentError, /expecting a hash/)
    end
  
    it "can address the first layer" do
      Layer1.new.fetch('bing').should be_kind_of(Layer1::Layer2)
    end
  
    it "can address a multi-layer address" do
      Layer1.new.fetch('bing.bam.boom').should == "Ouch!"
    end
  
    it "can fetch using the class method" do
      MP::Addressable.fetch('bing.bam.boom', :target => Layer1.new).should == "Ouch!"
    end
  
    it "raises an error when fetch is not given a target" do
      expect {
        MP::Addressable.fetch 'bing.bam.boom', :target => nil
      }.to raise_error(ArgumentError)
    end
  
    it "can address a hash and method chain mixture" do
      Layer1.new.fetch('bada.bing.bada.bam.bada.boom').should == 'Ouch!!!'
      Layer1.new.fetch('bada.bing.bada.bam.bada.boom.length').should == 7
    end
  
    it "fails when the hash key doesn't exist" do
      expect {
        Layer1.new.fetch('bada.boom', :raise_on_invalid => true)
      }.to raise_error(MP::Addressable::InvalidAddress)
    end
  
    it "fails when a method doesn't esits" do
      expect {
        Layer1.new.fetch('bing.bong', :raise_on_invalid => true)
      }.to raise_error(MP::Addressable::InvalidAddress)
    end
  
    it "can address an existing key that evaluates to nil" do
      Layer1.new.fetch('bada.nothing', :raise_on_invalid => true).should be_nil
    end
  end

  describe "match_head" do
    before :each do
      @addrs = ['fish.red_snapper', 'fish.bass', 'beer.bass', 'beer.yingling']
    end

    it "can use match_head to filter addresses" do
      matching = @addrs.select &MP::Addressable.match_head('fish')
      matching.should == ['fish.red_snapper', 'fish.bass']
    end
  
    it "can use match_head as an instance function" do
      matching = @addrs.select &Layer1.new.match_head('fish')
      matching.should == ['fish.red_snapper', 'fish.bass']
    end

    it "can take a symbol" do
      matching = @addrs.select &Layer1.new.match_head(:fish)
      matching.should == ['fish.red_snapper', 'fish.bass']
    end

    it "raises an error if not a string or symbol" do
      expect {
        @addrs.select &Layer1.new.match_head(1)
      }.to raise_error(ArgumentError, /string or symbol/)
    end
  end

  it "can get the head of an address using an instance" do
    Layer1.new.head("fish.bass").should == "fish"
  end

  it "can get the head of an address using the module" do
    MP::Addressable.head("fish.bass").should == "fish"
  end

  it "can get the tail of an address using an instance" do
    Layer1.new.tail("fish.bass.striped").should == "bass.striped"
  end

  it "can get the tail of an address using the module" do
    MP::Addressable.tail("fish.bass.striped").should == "bass.striped"
  end

  it "knows a one-segment address has no tail" do
    MP::Addressable.tail("fish").should be_nil
  end
end

# END
