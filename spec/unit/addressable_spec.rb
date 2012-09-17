require 'spec_helper'

describe "MongoPercolator::Addressable unit" do
  before :all do
    class Layer1
      include MongoPercolator::Addressable
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
    end
  end

  it "can address the first layer" do
    Layer1.new.fetch('bing').should be_kind_of(Layer1::Layer2)
  end

  it "can address a multi-layer path" do
    Layer1.new.fetch('bing.bam.boom').should == "Ouch!"
  end
end

