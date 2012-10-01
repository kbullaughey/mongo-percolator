require 'spec_helper.rb'

describe MongoPercolator do
  it { should respond_to(:whoami?) }

  it "deletes _id" do
    subject.dup_hash_selectively({'_id' => 1, 'other' => 2}).
      should == {'other' => 2}
  end

  it "deletes updated_at" do
    subject.dup_hash_selectively({'updated_at' => 1, 'other' => 2}).
      should == {'other' => 2}
  end

  it "deletes created_at" do
    subject.dup_hash_selectively({'created_at' => 1, 'other' => 2}).
      should == {'other' => 2}
  end

  it "can duplicate a one-level hash without ids" do
    hash = {'_id' => "fresh air", 'dave' => 'davies', 'terry' => 'gross'}
    hash_out = subject.dup_hash_selectively(hash)
    hash_out.should_not include('_id')
    hash.should include('_id')
    hash_out['dave'].should == 'davies'
    hash_out['terry'].should == 'gross'
  end

  it "can recursively duplicate a two-level hash involving an array" do
    hash = {'_id' => "fresh air", 'people' => [
      {'_id' => 'stand in', 'dave' => 'davies'},
      {'_id' => 'host',  'terry' => 'gross'}]}

    # Check the output hash
    hash_out = subject.dup_hash_selectively(hash)
    hash_out.should_not include('_id')
    hash_out['people'][0].should == {'dave' => 'davies'}
    hash_out['people'][1].should == {'terry' => 'gross'}
    hash_out.length.should == 1

    # Check the original hash
    hash['_id'].should == 'fresh air'
    hash['people'][0].should == {'_id' => 'stand in', 'dave' => 'davies'}
    hash['people'][1].should == {'_id' => 'host', 'terry' => 'gross'}
  end
end
