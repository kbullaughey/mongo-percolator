require 'spec_helper'

describe "Testing behavior of a MongoMapper::Document with a state_machine" do
  before :all do
    class DocWithStateMachine
      include MongoMapper::Document
      key :state, String
      key :times_save_called, Integer, :default => 0
      key :computed_property, String
      state_machine :state, :initial => :stale do
        state :stale
        state :current
        state :error
        state :holding

        event(:go_stale) { transition [:stale, :current] => :stale }
        event(:recompute) { transition [:stale, :current, :holding] => :current }
        event(:choke) { transition all => :error }

        before_transition [:stale, :current, :holding] => :current, :do => :compute
      end

      def save(*)
        self.times_save_called += 1
        super
      end

      def compute
        self.computed_property = "#{times_save_called} at #{state}"
      end
    end
  end

  before :each do
    DocWithStateMachine.remove
  end

  it "calls compute when transitioning from holding to current" do
    @doc = DocWithStateMachine.new
    @doc.state = "holding"
    @doc.times_save_called.should == 0
    @doc.recompute!
    @doc.times_save_called.should == 1
    @doc.computed_property.should == "1 at holding"
    @doc.current?.should be_true
    doc_persisted = DocWithStateMachine.first
    doc_persisted.times_save_called.should == 1
    doc_persisted.computed_property.should == "1 at holding"
  end

  it "calls compute when transitioning from stale to current" do
    @doc = DocWithStateMachine.new
    @doc.stale?.should be_true
    @doc.times_save_called.should == 0
    @doc.recompute!
    @doc.times_save_called.should == 1
    @doc.computed_property.should == "1 at stale"
    @doc.current?.should be_true
    doc_persisted = DocWithStateMachine.first
    doc_persisted.times_save_called.should == 1
    doc_persisted.computed_property.should == "1 at stale"
  end
end

# END
