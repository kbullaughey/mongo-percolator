require 'spec_helper'

describe "Learning how to use state_machine gem" do
  before :all do
    # Set up a test state machine
    class Pumpkin
      attr_accessor :state, :stolen
      def initialize
        super
      end

      def bump
        return true
      end

      state_machine :state, :initial => :in_garden, :action => :bump do
        state :in_garden
        state :picked
        state :purchased
        state :carved
        state :rotten
        state :cannon_fodder
        event(:pick) { transition :in_garden => :picked, :rotten => :cannon_fodder }
        event(:purchase) { transition :picked => :purchased }
        event :carve do 
          transition :picked => :carved, :if => lambda {|p| p.stolen}
          transition :purchased => :carved
        end
        event(:wait) { transition [:carved, :purchased] => :rotten }
        around_transition do |pumpkin, transition, block|
          block.call
        end
      end

      # Test whether a state-test method can be overriden
      def purchased?
        state == "purchased" or stolen == true
      end
    end
  end

  before :each do
    @pumpkin = Pumpkin.new
  end

  it "initial state is correct" do
    expect(@pumpkin.in_garden?).to be true
  end

  it "can transition to picked by picking" do
    @pumpkin.pick!
    expect(@pumpkin.picked?).to be true
  end

  it "can transition to cannon fodder if already rotten" do
    @pumpkin.pick!
    @pumpkin.purchase!
    @pumpkin.wait!
    @pumpkin.pick!
    expect(@pumpkin.cannon_fodder?).to be true
  end

  it "fails when an invalid event is tried" do
    expect {
      @pumpkin.purchase!
    }.to raise_error(StateMachines::InvalidTransition)
  end

  it "can't transition to carved if not purchases" do
    @pumpkin.pick!
    expect {
      @pumpkin.carve!
    }.to raise_error(StateMachines::InvalidTransition)
  end

  it "can transition to carved if not purchases when stolen" do
    @pumpkin.pick!
    @pumpkin.stolen = true
    expect {
      @pumpkin.carve!
    }.to_not raise_error
  end

  it "looks purchased when it was indeed purchased" do
    @pumpkin.pick!
    @pumpkin.purchase!
    expect(@pumpkin.purchased?).to be true
  end

  it "looks purchased when it's been stolen" do
    @pumpkin.pick!
    @pumpkin.stolen = true
    expect(@pumpkin.purchased?).to be true
  end

  it "doesn't look purchased if it's not been purchased or stolen" do
    @pumpkin.pick!
    expect(@pumpkin.purchased?).to be false
  end
end

# END
