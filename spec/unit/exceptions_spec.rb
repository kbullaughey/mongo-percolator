require 'spec_helper'

describe "StandardError enhancements" do
  it "can raise an exception with extra data and find it on rescue" do
    begin
      raise RuntimeError.new("something's afoot").add(:what => "end of the world")
    rescue RuntimeError => e
      e.extra.should == {:what => "end of the world"}
    end
  end
end

# END
