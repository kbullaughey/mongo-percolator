require 'active_support/concern'
require 'active_support/core_ext/string/inflections'

require 'mongo_mapper'
require 'mongo_percolator/version'

module MongoPercolator
  def self.whoami?
    'I am the (Mongo) Percolator!'
  end

  # Connect to the database. Only needed if MongoMapper is not otherwise connected.
  #
  # @param db [String] Mongo database name.
  def self.connect(db = "mongo_percolator_test")
    options = {}
    options[:safe] ||= {:w => 1}
    MongoMapper.connection = Mongo::Connection.new("localhost", nil, options)
    MongoMapper.database = db
    raise RuntimeError, "Failed to connect to MongoDB" if 
      MongoMapper.connection.nil?
    nil
  end

  # Duplicate a hash, but remove all the '_id' keys, recursively. Be careful 
  # about cycles.
  #
  # @param x [Hash] has to duplicate.
  # @return [Hash] Duplicated hash sans ids.
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
  # @return [Integer] Actual number of passes made.
  def self.percolate(max_passes = 1)
    passes = 0
    while passes < max_passes
      found_some = false
      Operation.where(:_old => true).find_each do |op|
        op.recompute!
        found_some = true
      end
      break unless found_some
      passes += 1
    end
    passes
  end
end

require 'mongo_percolator/addressable'
require 'mongo_percolator/addressable/diff'
require 'mongo_percolator/node_common'
require 'mongo_percolator/embedded_node'
require 'mongo_percolator/exceptions'
require 'mongo_percolator/many'
require 'mongo_percolator/node'
require 'mongo_percolator/operation'
require 'mongo_percolator/parent_meta'

# END
