require 'spec_helper.rb'

describe MongoPercolator do
  it { expect(subject).to respond_to(:whoami?) }

  it "deletes _id" do
    expect(subject.dup_hash_selectively({'_id' => 1, 'other' => 2})).to eq({'other' => 2})
  end

  it "deletes updated_at" do
    expect(subject.dup_hash_selectively({'updated_at' => 1, 'other' => 2})).to eq({'other' => 2})
  end

  it "deletes created_at" do
    expect(subject.dup_hash_selectively({'created_at' => 1, 'other' => 2})).to eq({'other' => 2})
  end

  it "can duplicate a one-level hash without ids" do
    hash = {'_id' => "fresh air", 'dave' => 'davies', 'terry' => 'gross'}
    hash_out = subject.dup_hash_selectively(hash)
    expect(hash_out).to_not include('_id')
    expect(hash).to include('_id')
    expect(hash_out['dave']).to eq('davies')
    expect(hash_out['terry']).to eq('gross')
  end

  it "can recursively duplicate a two-level hash involving an array" do
    hash = {'_id' => "fresh air", 'people' => [
      {'_id' => 'stand in', 'dave' => 'davies'},
      {'_id' => 'host',  'terry' => 'gross'}]}

    # Check the output hash
    hash_out = subject.dup_hash_selectively(hash)
    expect(hash_out).to_not include('_id')
    expect(hash_out['people'][0]).to eq({'dave' => 'davies'})
    expect(hash_out['people'][1]).to eq({'terry' => 'gross'})
    expect(hash_out.length).to eq(1)

    # Check the original hash
    expect(hash['_id']).to eq('fresh air')
    expect(hash['people'][0]).to eq({'_id' => 'stand in', 'dave' => 'davies'})
    expect(hash['people'][1]).to eq({'_id' => 'host', 'terry' => 'gross'})
  end
end
