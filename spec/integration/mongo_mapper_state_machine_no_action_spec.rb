require 'spec_helper'

describe "Testing behavior of a MongoMapper::Document state_machine w/o action" do
  before :all do
    class DocWithStateMachine2
      include MongoMapper::Document
      key :state, String
      key :times_save_called, Integer, :default => 0
      key :computed_property, String
      state_machine :state, :initial => :stale, :action => nil do
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
    clean_db
  end

  it "calls compute when transitioning from holding to current" do
    @doc = DocWithStateMachine2.new
    @doc.state = "holding"
    @doc.times_save_called.should == 0
    @doc.recompute!
    @doc.persisted?.should be_false
    @doc.times_save_called.should == 0
    @doc.computed_property.should == "0 at holding"
    @doc.current?.should be_true
    @doc.save.should be_true
    @doc.times_save_called.should == 1
    doc_persisted = DocWithStateMachine2.first
    doc_persisted.times_save_called.should == 1
    doc_persisted.computed_property.should == "0 at holding"
  end
end

# END
