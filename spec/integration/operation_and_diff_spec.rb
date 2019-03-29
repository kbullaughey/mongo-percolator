require 'spec_helper'

describe "Diffs on operation parents" do
  before :all do
    class Queen2
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
        declare_parent :queen, :class => Queen2
        depends_on 'queen.description.name'
      end
      include MongoPercolator::Node
      operation :op, Op
    end

    class Nest2
      class Op < MongoPercolator::Operation
        emit {}
        declare_parent :queen, :class => Queen2
        depends_on 'queen.description.body_segments.triats.color'
      end
      include MongoPercolator::Node
      operation :op, Op
    end

  end

  before :each do
    clean_db
    @queen = Queen2.new :description => Queen2.starter
    @queen.save!
  end

  context "Nest1" do
    before :each do
      @op = Nest1::Op.new :queen => @queen
      @nest = Nest1.new :op => @op
      @nest.save!
    end
  
    it "has no relevant changes at the beginning" do
      expect(@nest.op.relevant_changes_for(@queen)).to be_empty
    end
  
    it "includes name in the relevant change" do
      @queen.description['name'] = "Barbara"
      expect(@op.relevant_changes_for(@queen)).to include('queen.description.name')
    end

    it "can find relevant changes against any object" do
      original = @queen.to_mongo
      modified = @queen.to_mongo
      modified['description'] = modified['description'].dup
      modified['description']['name'] = "Sue"
      expect(@nest.op.relevant_changes_for(@queen, :against => original)).to be_empty
      expect(@nest.op.relevant_changes_for(@queen, :against => modified)).to_not be_empty
    end
  end
end

# END

