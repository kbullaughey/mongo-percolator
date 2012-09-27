require 'spec_helper'

describe "MongoPercolator::Addressable unit" do
  before :all do
    ::MP = MongoPercolator unless Object.const_defined? :MP
    class Layer1
      include MP::Addressable
      class Layer2
        attr_accessor :id
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
      def powpowpow
        [{:id => '1', :sound => 'eeek'}, {:id => '2', :sound => 'aaaah'}]
      end
      def kazam!
        o1 = Layer2.new
        o1.id = 'a'
        o2 = Layer2.new
        o2.id = 'b'
        [o1, o2]
      end
      def bada
        {:bing => {'bada' => {'bam' => {'bada' => {'boom' => 'Ouch!!!'}}}}, :nothing => nil}
      end
    end
  end

  it "can regognize an array key" do
    MP::Addressable.array?('array[123]').should be_true
  end

  it "knows when a key is not an array (1)" do
    MP::Addressable.array?('array[]').should be_false
  end

  it "knows when a key is not an array (2)" do
    MP::Addressable.array?('array[').should be_false
  end

  it "knows when a key is not an array (3)" do
    MP::Addressable.array?('array]').should be_false
  end

  it "knows when a key is not an array (3)" do
    MP::Addressable.array?('[]').should be_false
  end

  it "knows when a key is not an array (3)" do
    MP::Addressable.array?('blah').should be_false
  end

  it "can extract the array name" do
    MP::Addressable.array_name('array[123]').should == "array"
  end

  it "can extract a single-character array name" do
    MP::Addressable.array_name('a[123]').should == "a"
  end

  it "can extract the array index" do
    MP::Addressable.array_index('array[123]').should == '123'
  end

  it "can regognize a valid array segment" do
    MP::Addressable.valid_segment?('array[123]').should be_true
  end

  it "can recognize a valid segment that's not an array segment" do
    MP::Addressable.valid_segment?('not_an_array').should be_true
  end

  it "knows two indices is invalid" do
    MP::Addressable.valid_segment?('[a][b]').should be_false
  end

  it "knows two empty indices is invalid" do
    MP::Addressable.valid_segment?('[][]').should be_false
  end

  it "knows an index missing an open is invalid" do
    MP::Addressable.valid_segment?('array]').should be_false
  end

  it "knows an index missing a close is invalid" do
    MP::Addressable.valid_segment?('array[').should be_false
  end

  it "knows an empty string is invalid" do
    MP::Addressable.valid_segment?('').should be_false
  end

  it "knows an array with no label is invalid" do
    MP::Addressable.valid_segment?('[123]').should be_false
  end

  it "knows funny characters in the index is okay" do
    MP::Addressable.valid_segment?('array[@$@%"]').should be_true
  end

  it "knows an invalid character is invalid" do
    MP::Addressable.valid_segment?('@').should be_false
  end

  it "knows an invalid character in the array name is invalid" do
    MP::Addressable.valid_segment?('arr@y[123]').should be_false
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

    it "can fetch from an array" do
      res = Layer1.new.fetch('powpowpow[1]')
      res.should_not be_nil
      res[:sound].should == 'eeek'
    end

    it "can fetch into an object within an array item" do
      Layer1.new.fetch('kazam![b].bam.boom').should == "Ouch!"
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

  describe "find_in_array" do
    it "can use id symbols in a hash" do
      target = [{:id => :okay}, {:id => :fail}]
      MP::Addressable.find_in_array("okay", target).should == {:id => :okay}
    end

    it "can use ObjectIds in a hash" do
      target = [{:id => BSON::ObjectId('5064cfe1a0b7f96cb9000008')}, 
        {:id => BSON::ObjectId('5064cfe1a0b7f96cb9000009')}]
      MP::Addressable.find_in_array("5064cfe1a0b7f96cb9000008", target).should == 
        {:id => BSON::ObjectId('5064cfe1a0b7f96cb9000008')}
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
