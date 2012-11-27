require 'spec_helper'

describe "Diffs on operation parents" do
  before :all do
    class Queen
      include MongoPercolator::Node
      key :description, Hash
      
      # A fixture
      def self.starter
        {'body_segments' => [
            {'segment' => 'thorax', 'triats' => {'color' => 'black', 'size' => 4}},
            {'segment' => 'abdomen', 'traits' => {'color' => 'brown', 'size' => 3}},
            {'segment' => 'head', 'triats'  => {'color' => 'tan', 'size' => 1}}],
          'name' => 'Alicia Maria Jobug'}
      end
    end

    class Nest1
      class Op < MongoPercolator::Operation
        emit {}
        declare_parent :queen
        depends_on 'queen.description.name'
      end
      include MongoPercolator::Node
      operation :op, Op
    end

    class Nest2
      class Op < MongoPercolator::Operation
        emit {}
        declare_parent :queen
        depends_on 'queen.description.body_segments.triats.color'
      end
      include MongoPercolator::Node
      operation :op, Op
    end

  end

  before :each do
    Queen.remove
    MongoPercolator::Operation.remove
    @queen = Queen.new :description => Queen.starter
    @queen.save!
  end

  context "Nest1" do
    before :each do
      Nest1.remove
      @op = Nest1::Op.new :queen => @queen
      @nest = Nest1.new :op => @op
      @nest.save!
    end
  
    it "has no relevant changes at the beginning" do
      @nest.op.relevant_changes_for(@queen).should be_empty
    end
  
    it "includes name in the relevant change" do
      @queen.description['name'] = "Barbara"
      @op.relevant_changes_for(@queen).should include('queen.description.name')
    end

    it "can find relevant changes against any object" do
      original = @queen.to_mongo
      modified = @queen.to_mongo
      modified['description'] = modified['description'].dup
      modified['description']['name'] = "Sue"
      @nest.op.relevant_changes_for(@queen, :against => original).should be_empty
      @nest.op.relevant_changes_for(@queen, :against => modified).should_not be_empty
    end
  end
end

# END

