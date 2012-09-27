FactoryGirl.define do
  factory 'mongo_percolator/many/copy' do
    ids ['a', 'b']
    node_id ['c']
    path 'd'
  end
end
