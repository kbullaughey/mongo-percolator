FactoryGirl.define do
  factory 'mongo_percolator/many/copy' do
    ids ['a', 'b']
    root_id ['c']
    label 'd'
  end
end
