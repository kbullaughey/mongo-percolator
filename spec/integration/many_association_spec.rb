require 'spec_helper'

describe "MongoPercolator many association (integration)" do
  before :all do
    class Dugong
      include MongoPercolator::Node
    end
    class TestManyAssociation1
      include MongoPercolator::Node
      
      key :dugong_ids
      many :dugongs, :in => :dugong_ids
    end
  end

  it "created the many association" do
  end
end

# END



