require 'mongo_mapper'
require 'mongo_percolator/version'

module MongoPercolator
  def self.whoami?
    'I am the (Mongo) Percolator!'
  end
end

require 'mongo_percolator/operation_definition'
