require 'spec_helper'

describe "Testing ActiveModel Callbacks in MongoMapper" do
  before :all do
    class TempermentCallbackTest
      include MongoMapper::Document
      key :location, String
      before_save :jump_out_window, :if => Proc.new {|obj| obj.suicidal }
      attr_accessor :suicidal
      def jump_out_window
        self.location = "ground"
        return false
      end
    end
  end

  before :each do
    clean_db
    @stupid = TempermentCallbackTest.new :location => "top floor"
  end

  it "executes the callback when the condition is true" do
    @stupid.suicidal = true
    @stupid.save.should be_false
    @stupid.location.should == "ground"
    TempermentCallbackTest.first.should be_nil
  end

  it "doesn't execute the callback when the condition is false" do
    @stupid.save.should be_true
    @stupid.location.should == "top floor"
    TempermentCallbackTest.first.should_not be_nil
  end
end

# END
