# This file was generated by the `rspec --init` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# Require this file using `require "spec_helper"` to ensure that it is only
# loaded once.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'
end

# A convenience function for keeping the database clean. This can be run in a 
# before(:each) handler of integration tests that change the database state.
def clean_db
  db = MongoMapper.database
  collections = db.collection_names - ["system.indexes", "system.profile"]
  collections.each{|c| db[c].drop }
end

require 'bundler/setup'
require 'pry'
require 'mongo_percolator'

# Connect our test database
MongoPercolator.connect
clean_db

# Use factory girl for fixtures
require 'factory_girl'
FactoryGirl.find_definitions
