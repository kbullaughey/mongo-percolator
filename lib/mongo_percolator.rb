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
    raise RuntimeError, "Failed to connect to MongoDB" if 
      MongoMapper.connection.nil?
  end

  # Duplicate a hash, but remove all the '_id' keys, recursively. Be careful 
  # about cycles.
  def self.dup_hash_without_ids(x)
    if x.kind_of? Hash
      x = Hash[x.each.collect {|k,v| [k, dup_hash_without_ids(v)] }]
      x.delete '_id'
    elsif x.kind_of? Array
      x = x.collect {|v| dup_hash_without_ids(v) }
    end
    x
  end

  # Recompute everything
  # 
  # @param max_passes [Integer] Do at most this number of passes. If there are
  #   no more updates, stop.
  def self.percolate(max_passes = 1)
    while max_passes > 0
      found_some = false
      Operation.where(:_old => true).find_each do |op|
        op.recompute!
        found_some = true
      end
      break unless found_some
      max_passes -= 1
    end
  end
end

require 'mongo_percolator/addressable'
require 'mongo_percolator/addressable/diff'
require 'mongo_percolator/exceptions'
require 'mongo_percolator/node'
require 'mongo_percolator/operation'
