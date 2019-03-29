require 'spec_helper'

describe "MongoPercolator Node & Operation integration" do
  before :all do
    # This will serve as the parent class
    class AnimalsIntegration
      include MongoPercolator::Node
      key :wild, Array
      key :farm, Array
      key :imaginary, Array
    end

    # Set up an operation class
    class RealOp < MongoPercolator::Operation
      emit do
        raise "Purposeful failure" unless self['should_fail'].nil?
        self.pets = ((input('animals.farm')||[]) + (input('animals.wild')||[])).sort
      end
      declare_parent :animals, :class => AnimalsIntegration
      depends_on 'animals.farm'
      depends_on 'animals.wild'
    end

    # Set up a node class
    class SomeNode
      include MongoPercolator::Node
      operation :real_op, RealOp
      key :pets, Array
    end

    # A node with a required property
    class SomeNodeWithRequirement
      include MongoPercolator::Node
      class Op < MongoPercolator::Operation
        emit {}
      end
      operation :op
      key :name, String, :required => true
    end

    class SomeOtherNode
      include MongoPercolator::Node
      operation :real_op, RealOp
      key :pets, Array
    end
  end

  before :each do
    clean_db
  end

  describe "RealOp" do
    before :each do
      @animals = AnimalsIntegration.new
      @op = RealOp.new
    end

    it "is frozen" do
      expect(RealOp.parent_labels.frozen?).to be true
    end

    it "persists the parent on assignment" do
      @op.animals = @animals
      expect(@animals.persisted?).to be true
      expect(AnimalsIntegration.where(:id => @animals.id).count).to eq(1)
    end

    it "doesn't leave any traces if it fails in emit" do
      @animals['should_fail'] = 'yes'
      expect {
        @op.perform_on!(@animals)
      }.to raise_error(RuntimeError, /Purposeful failure/)
      expect(MongoPercolator::Operation.count).to eq(0)
      expect(AnimalsIntegration.count).to eq(0)
    end

    it "can access the parent using the reader" do
      @op.animals = @animals
       expect(@op.animals).to eq(@animals)
    end

    it "has a one association" do
      expect(@op).to respond_to(:node)
    end

    it "has the correct parent labels" do
       expect(RealOp.parent_labels.to_a).to eq([:animals])
    end

    it "allows operations to be added to another class" do
      node = SomeOtherNode.create!
      node.create_real_op :animals => AnimalsIntegration.new(:wild => ['baboon'])
      node.real_op.perform!
      node.reload
      expect(node.pets).to include('baboon')
    end

    it "can be performed when the op is created separately" do
      op = RealOp.new
      node = SomeOtherNode.new :real_op => op
      node.real_op.perform_on! node
    end

    it "sets up the node when using the create convenience function" do
      node = SomeOtherNode.new
      node.create_real_op :animals => AnimalsIntegration.new(:wild => ['baboon'])
      expect(node).to_not be_persisted
      op = node.real_op
      expect(op).to be_persisted
      expect(op).to be_naive
      expect(node.save).to be true
      op.reload
      expect(op).to be_available
    end

    it "fails when passed a malformed label" do
      expect {
        class YetAnotherNode
          include MongoPercolator::Node
          operation :"not okay", RealOp
        end
      }.to raise_error(ArgumentError, /Malformed label/)
    end

    it "fails when not passed a class as the second param" do
      expect {
        class YetAnotherNode
          include MongoPercolator::Node
          operation :label, "not a class"
        end
      }.to raise_error(ArgumentError, /Expecting class/)
    end

    context "populated AnimalsIntegration" do
      before :each do
        @animals = AnimalsIntegration.new :wild => %w(sloth binturong)
        @op.animals = @animals
      end

      it "saves the parent on assignment" do
        expect(@animals).to be_persisted
      end

      it "knows which dependencies have changed (1)" do
        @animals.wild << 'meerkat'
         expect(@op.relevant_changes_for(@animals)).to eq(['animals.wild'])
      end
  
      it "knows which dependencies have changed (2)" do
        @animals.wild << 'meerkat'
        @animals.farm = ['pig']
        expect(@op.relevant_changes_for(@animals).sort).to eq(%w(animals.farm animals.wild))
      end
    end
  end

  describe "SomeNodeWithRequirement" do
    it "can be performed when the op is created separately" do
      op = SomeNodeWithRequirement::Op.new
      node = SomeNodeWithRequirement.new :op => op
      expect(node).to_not be_persisted
      node.name = "King George"
      node.op.perform_on! node
    end
  end

  describe "SomeNode" do
    before :each do
      @node = SomeNode.new
      @animals = AnimalsIntegration.new :wild => %w(sloth binturong dugong)
      @op = RealOp.new :animals => @animals
    end

    it "can be performed when the op is created separately and has a parent" do
      node = SomeOtherNode.new :real_op => @op
      node.real_op.perform_on! node
    end

    it "has an operation association" do
      expect(@node).to respond_to(:real_op)
    end
    
    context "has an op associated" do
      before :each do
        @node.real_op = @op
        @node.save!
      end

      it "has a real op associated" do
        expect(@node.real_op).to be_kind_of(RealOp)
      end

      it "can find the node from the real op" do
        expect(@op.node).to be_kind_of(SomeNode)
      end
  
      it "can compute computed properties on demand" do
         expect(@node.pets).to eq([])
        @op.perform!
        @node.reload
         expect(@node.pets).to eq(%w(binturong dugong sloth))
      end

      it "destroys its operations when node is destroyed" do
        real_op_id = @node.real_op.id
        node_id = @node.id
        expect(RealOp.find(real_op_id)).to_not be_nil
        @node.destroy
        expect(SomeNode.find(node_id)).to be_nil
        expect(RealOp.find(real_op_id)).to be_nil
      end

      it "destroys the old operation when it's replaced" do
        old_id = @node.real_op.id
        expect(RealOp.find(old_id)).to_not be_nil
        new_op = RealOp.new :animals => @animals
        @node.real_op = new_op
         expect(@node.real_op.id).to_not eq(old_id)
        expect(RealOp.find(old_id)).to be_nil
      end

      context "computed initially" do
        before :each do
          @op.perform!
          @node.reload
        end

        it "should be marked as old when the parent is changed" do
          expect(@node.real_op.stale?).to be false
          @animals.farm = ['hog']
          @animals.save!
          @node.reload
          expect(@node.real_op.stale?).to be true
        end

        it "should be marked as old when the identity of the parent changes" do
          expect(@node.real_op.stale?).to be false
          new_animals = AnimalsIntegration.create :farm => ['sheep']
          expect(new_animals).to_not be_nil
          @node.real_op.animals = new_animals
          expect(@node.real_op.save).to be true
          expect(@node.real_op.stale?).to be true
        end
    
        it "gets an updated computed property when the parent is changed" do
          @animals.farm = ['hog']
          @animals.save
          expect(MongoPercolator::Operation.where(:stale => true).count).to eq(1)
          expect(MongoPercolator.percolate.operations).to eq(1)
          @node.reload
           expect(@node.pets).to eq(%w(binturong dugong hog sloth))
        end

        it "is no longer marked as old after percolation" do
          @animals.farm = ['hog']
          expect(@animals.save).to be true
          expect(MongoPercolator.percolate.operations).to eq(1)
          @node.reload
          expect(@node.real_op.stale?).to be false
        end

        it "only takes the number of passes needed" do
          @animals.farm = ['hog']
          @animals.save
          expect(MongoPercolator.percolate.operations).to eq(1)
        end

        it "can use the guide to percolate" do
          @animals.farm = ['hog']
          @animals.save
          expect(MongoPercolator.guide.percolate.operations).to eq(1)
        end

        it "uses the cache when computing dependencies" do
          node2 = SomeNode.new
          op2 = RealOp.new :animals => @animals
          node2.real_op = op2
          op2.save!
          node2.save!
          expect(RealOp).to receive(:relevant_changes_for).once.and_call_original
          @animals.save!
        end
      end
    end
  end

  pending "check that multiple parents of same class work (#{__FILE__})"
  pending "check parents can be out of order when using :position (#{__FILE__})"
  pending "check that parents can have gaps when using :position (#{__FILE__})"
  pending "check that computes can compute vaious associations (#{__FILE__})"
  pending "check that state variables are not overwritten on save (#{__FILE__})"
  pending "check that timeid is updating each place it should (#{__FILE__})"
end
