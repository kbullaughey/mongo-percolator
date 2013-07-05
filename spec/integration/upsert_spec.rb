require 'spec_helper'

describe "upserts on nodes" do
  before :all do
    class TargetBeingFollowed
      include MongoPercolator::Node
      key :name, String
      key :secret, String
      key :hair_color, String
      key :create_counter, Integer, :default => 0
      key :save_counter, Integer, :default => 0
      before_save { self.save_counter += 1 }
      after_create { increment :create_counter => 1 }
    end

    class SpecialAgent1
      include MongoPercolator::Node
      class Track < MongoPercolator::Operation
        declare_parent :target, :class => TargetBeingFollowed
        depends_on 'target.name'
        depends_on 'target.hair_color'
        emit do
          self.following = "#{input 'target.name'} with #{input 'target.hair_color'} hair"
        end
      end
      operation :track
      key :following, String
    end
  end

  before :each do
    clean_db
    @target = TargetBeingFollowed.create! :name => "Mr. Bond",
      :secret => "I have six toes on my left foot",
      :hair_color => "black"
    @agent = SpecialAgent1.new
    @agent.create_track :target => @target
    @agent.save!
    MongoPercolator.percolate
    @agent.reload
    @target.reload
  end

  it "starts following the target" do
    @agent.following.should == "Mr. Bond with black hair"
  end

  it "knows it's been created" do
    @target.create_counter.should == 1
  end

  it "knows its been saved" do
    @target.save_counter.should == 1
  end

  it "percolates when the target is upserted" do
    MongoPercolator::Operation.first.should_not be_stale
    TargetBeingFollowed.where(:name => "Mr. Bond").upsert(:$set => {:name => "James"})
    MongoPercolator::Operation.first.should be_stale
    MongoPercolator.percolate
    @agent.reload
    @agent.following.should == "James with black hair"
    @target.reload
    @target.save_counter.should == 2
  end

  it "runs the create and save callbacks when upserting a non-existant document" do
    TargetBeingFollowed.collection.remove
    TargetBeingFollowed.where(:name => "Jamesypie").upsert(:$set => {:hair_color => "(bald)"})
    @target = TargetBeingFollowed.first
    @target.name.should == "Jamesypie"
    @target.hair_color.should == "(bald)"
    @target.save_counter.should == 1
    @target.create_counter.should == 1
  end

  it "doesn't percolate when an unwatched property is upserted" do
    TargetBeingFollowed.where(:name => "Mr. Bond").upsert :$set => 
      {:secret => "I'm scared of blueberry muffins."}
    MongoPercolator::Operation.first.should_not be_stale
    @target.reload
  end

  it "forces propagation when the document was created between operations" do
    TargetBeingFollowed.collection.remove
    # When I call find and modify, I actually create the document, but return nil.
    # This has the effect of the document not existing initially, but being
    # concurrently created by some other process.
    TargetBeingFollowed.stub(:find_and_modify) do |opts|
      query = opts[:query]
      query[:name].should == "Mr. Bond"
      doc = {:secret => "I dream of refridgerators", :hair_color => "green"}
      @target = TargetBeingFollowed.create! query.merge(doc)
      # I need to set up the agent to track this document so I can test percolation
      @agent.track.target = @target
      @agent.track.save!
      MongoPercolator.percolate
      nil
    end

    TargetBeingFollowed.where(:name => "Mr. Bond").upsert(:$set => {:hair_color => "blond"})
    MongoPercolator.percolate

    @agent.reload
    @agent.following.should == "Mr. Bond with blond hair"
    @target.secret.should == "I dream of refridgerators"
  end
end

# END
