require 'mongo_mapper'
require 'mongo_percolator/version'

module MongoPercolator
  def self.whoami?
    'I am the (Mongo) Percolator!'
  end

  def self.connect(db = "mongo_percolator_test")
    options = {}
    options[:safe] ||= {:w => 1}
    MongoMapper.connection = Mongo::Connection.new("localhost", nil, options)
    MongoMapper.database = db
    raise RuntimeError, "Failed to connect to MongoDB" if MongoMapper.connection.nil?
  end
end

require 'mongo_percolator/addressable'
require 'mongo_percolator/exceptions'
require 'mongo_percolator/node'
require 'mongo_percolator/operation_definition'
