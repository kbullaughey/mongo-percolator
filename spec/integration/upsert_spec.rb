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
     expect(@agent.following).to eq("Mr. Bond with black hair")
  end

  it "knows it's been created" do
    expect(@target.create_counter).to eq(1)
  end

  it "knows its been saved" do
    expect(@target.save_counter).to eq(1)
  end

  it "percolates when the target is upserted" do
    expect(MongoPercolator::Operation.first).to_not be_stale
    TargetBeingFollowed.where(:name => "Mr. Bond").upsert(:$set => {:name => "James"})
    expect(MongoPercolator::Operation.first).to be_stale
    MongoPercolator.percolate
    @agent.reload
     expect(@agent.following).to eq("James with black hair")
    @target.reload
    expect(@target.save_counter).to eq(2)
  end

  it "runs the create and save callbacks when upserting a non-existant document" do
    TargetBeingFollowed.collection.remove
    TargetBeingFollowed.where(:name => "Jamesypie").upsert(:$set => {:hair_color => "(bald)"})
    @target = TargetBeingFollowed.first
     expect(@target.name).to eq("Jamesypie")
     expect(@target.hair_color).to eq("(bald)")
    expect(@target.save_counter).to eq(1)
    expect(@target.create_counter).to eq(1)
  end

  it "doesn't percolate when an unwatched property is upserted" do
    TargetBeingFollowed.where(:name => "Mr. Bond").upsert :$set => 
      {:secret => "I'm scared of blueberry muffins."}
    expect(MongoPercolator::Operation.first).to_not be_stale
    @target.reload
  end

  it "forces propagation when the document was created between operations" do
    TargetBeingFollowed.collection.remove
    # When I call find and modify, I actually create the document, but return nil.
    # This has the effect of the document not existing initially, but being
    # concurrently created by some other process.
    TargetBeingFollowed.stub(:find_and_modify) do |opts|
      query = opts[:query]
       expect(query[:name]).to eq("Mr. Bond")
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
     expect(@agent.following).to eq("Mr. Bond with blond hair")
     expect(@target.secret).to eq("I dream of refridgerators")
  end
end

# END
