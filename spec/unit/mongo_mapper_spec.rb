require 'spec_helper'

describe "MongoMapper" do
  before :all do
    class Mm1
      include MongoMapper::Document
      belongs_to :mm2
    end

    class Mm2
      include MongoMapper::Document
      one :mm1
    end
  end

  it "is not persisted when it has an association" do
    mm1 = Mm1.new
    mm2 = Mm2.new :mm1 => mm1
    expect(mm1).to be_persisted
    expect(mm2).to be_persisted
  end
end

# END
