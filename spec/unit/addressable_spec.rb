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
    expect(MP::Addressable.array?('array[123]')).to be true
  end

  it "knows when a key is not an array (1)" do
    expect(MP::Addressable.array?('array[]')).to be false
  end

  it "knows when a key is not an array (2)" do
    expect(MP::Addressable.array?('array[')).to be false
  end

  it "knows when a key is not an array (3)" do
    expect(MP::Addressable.array?('array]')).to be false
  end

  it "knows when a key is not an array (3)" do
    expect(MP::Addressable.array?('[]')).to be false
  end

  it "knows when a key is not an array (3)" do
    expect(MP::Addressable.array?('blah')).to be false
  end

  it "can extract the array name" do
     expect(MP::Addressable.array_name('array[123]')).to eq("array")
  end

  it "can extract a single-character array name" do
     expect(MP::Addressable.array_name('a[123]')).to eq("a")
  end

  it "can extract the array index" do
     expect(MP::Addressable.array_index('array[123]')).to eq('123')
  end

  it "can regognize a valid array segment" do
    expect(MP::Addressable.valid_segment?('array[123]')).to be true
  end

  it "can recognize a valid segment that's not an array segment" do
    expect(MP::Addressable.valid_segment?('not_an_array')).to be true
  end

  it "knows two indices is invalid" do
    expect(MP::Addressable.valid_segment?('[a][b]')).to be false
  end

  it "knows two empty indices is invalid" do
    expect(MP::Addressable.valid_segment?('[][]')).to be false
  end

  it "knows an index missing an open is invalid" do
    expect(MP::Addressable.valid_segment?('array]')).to be false
  end

  it "knows an index missing a close is invalid" do
    expect(MP::Addressable.valid_segment?('array[')).to be false
  end

  it "knows an empty string is invalid" do
    expect(MP::Addressable.valid_segment?('')).to be false
  end

  it "knows an array with no label is invalid" do
    expect(MP::Addressable.valid_segment?('[123]')).to be false
  end

  it "knows funny characters in the index is okay" do
    expect(MP::Addressable.valid_segment?('array[@$@%"]')).to be true
  end

  it "knows an invalid character is invalid" do
    expect(MP::Addressable.valid_segment?('@')).to be false
  end

  it "knows an invalid character in the array name is invalid" do
    expect(MP::Addressable.valid_segment?('arr@y[123]')).to be false
  end

  it "can recognize a splat" do
    expect(MP::Addressable.splat?('arry[]')).to be true
  end

  it "sees a splat as a valid segment" do
    expect(MP::Addressable.valid_segment?('arry[]')).to be true
  end

  it "can extract the splat label" do
     expect(MP::Addressable.splat_label('arry[]')).to eq("arry")
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
      }.to raise_error(ArgumentError, /Expecting a hash/)
    end
  
    it "can address the first layer as single" do
      expect(Layer1.new.fetch('bing', :single => true)).to be_kind_of(Layer1::Layer2)
    end
  
    it "can address the first layer" do
      match = Layer1.new.fetch('bing')
      expect(match.length).to eq(1)
      expect(match.first).to be_kind_of(Layer1::Layer2)
    end
  
    it "can address a multi-layer address" do
       expect(Layer1.new.fetch('bing.bam.boom', :single => true)).to eq("Ouch!")
       expect(Layer1.new.fetch('bing.bam.boom')).to eq(["Ouch!"])
    end

    it "can fetch from an array (single)" do
      res = Layer1.new.fetch('powpowpow[1]', :single => true)
      expect(res).to_not be_nil
       expect(res[:sound]).to eq('eeek')
    end

    it "can fetch from an array" do
      res = Layer1.new.fetch('powpowpow[1]')
      expect(res.length).to eq(1)
       expect(res.first[:sound]).to eq('eeek')
    end

    it "can fetch into an object within an array item" do
       expect(Layer1.new.fetch('kazam![b].bam.boom', :single => true)).to eq("Ouch!")
    end

    it "can fetch multiple items from an array (1)" do
       expect(Layer1.new.fetch('kazam![].bam.boom')).to eq(["Ouch!"] * 2)
    end

    it "can fetch multiple items from an array (2)" do
       expect(Layer1.new.fetch('powpowpow[].sound')).to eq(['eeek', 'aaaah'])
    end

    it "can fetch into an object within an array item" do
       expect(Layer1.new.fetch('kazam![b].bam.boom')).to eq(["Ouch!"])
    end

    it "can fetch using the class method" do
      expect(MP::Addressable.fetch('bing.bam.boom', :target => Layer1.new, single: true)).to eq("Ouch!")
    end
  
    it "raises an error when fetch is not given a target" do
      expect {
        MP::Addressable.fetch 'bing.bam.boom', :target => nil
      }.to raise_error(ArgumentError)
    end
  
    it "can address a hash and method chain mixture (single)" do
      expect(Layer1.new.fetch('bada.bing.bada.bam.bada.boom', :single => true)).to eq('Ouch!!!')
      expect(Layer1.new.fetch('bada.bing.bada.bam.bada.boom.length', :single => true)).to eq(7)
    end
  
    it "can address a hash and method chain mixture" do
       expect(Layer1.new.fetch('bada.bing.bada.bam.bada.boom')).to eq(['Ouch!!!'])
       expect(Layer1.new.fetch('bada.bing.bada.bam.bada.boom.length')).to eq([7])
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
      expect(Layer1.new.fetch('bada.nothing', :raise_on_invalid => true, single: true)).to be_nil
    end

    it "can address an existing key that evaluates to nil" do
      expect(Layer1.new.fetch('bada.nothing', :raise_on_invalid => true)).to eq([nil])
    end
  end

  describe "find_in_array" do
    it "can use id symbols in a hash" do
      target = [{:id => :okay}, {:id => :fail}]
      expect(MP::Addressable.find_in_array("okay", target)).to eq({:id => :okay})
    end

    it "can use ObjectIds in a hash" do
      target = [{:id => BSON::ObjectId('5064cfe1a0b7f96cb9000008')}, 
        {:id => BSON::ObjectId('5064cfe1a0b7f96cb9000009')}]
      expect(MP::Addressable.find_in_array("5064cfe1a0b7f96cb9000008", target)).to eq({:id => BSON::ObjectId('5064cfe1a0b7f96cb9000008')})
    end
  end

  describe "match_head" do
    before :each do
      @addrs = ['fish.red_snapper', 'fish.bass', 'beer.bass', 'beer.yingling']
    end

    it "can use match_head to filter addresses" do
      matching = @addrs.select &MP::Addressable.match_head('fish')
      expect(matching).to eq(['fish.red_snapper', 'fish.bass'])
    end
  
    it "can use match_head as an instance function" do
      matching = @addrs.select &Layer1.new.match_head('fish')
      expect(matching).to eq(['fish.red_snapper', 'fish.bass'])
    end

    it "can take a symbol" do
      matching = @addrs.select &Layer1.new.match_head(:fish)
      expect(matching).to eq(['fish.red_snapper', 'fish.bass'])
    end

    it "raises an error if not a string or symbol" do
      expect {
        @addrs.select &Layer1.new.match_head(1)
      }.to raise_error(ArgumentError, /string or symbol/)
    end
  end

  it "can get the head of an address using an instance" do
    expect(Layer1.new.head("fish.bass")).to eq("fish")
  end

  it "can get the head of an address using the module" do
    expect(MP::Addressable.head("fish.bass")).to eq("fish")
  end

  it "can get the tail of an address using an instance" do
    expect(Layer1.new.tail("fish.bass.striped")).to eq("bass.striped")
  end

  it "can get the tail of an address using the module" do
    expect(MP::Addressable.tail("fish.bass.striped")).to eq("bass.striped")
  end

  it "knows a one-segment address has no tail" do
    expect(MP::Addressable.tail("fish")).to be_nil
  end
end

# END
