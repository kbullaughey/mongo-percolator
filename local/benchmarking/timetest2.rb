#!/usr/bin/env ruby

require 'mongo_percolator'
MongoPercolator.connect

class TimeTest2
  include MongoMapper::Document
  key :timeid, BSON::ObjectId
  key :counter, Integer

  before_save :update_timeid

  def update_timeid
    self.timeid = BSON::ObjectId.new
  end
end

1.upto(10000) do |i|
  TimeTest2.create! :counter => i
end

puts "#{TimeTest2.count} TimeTest2 documents inserted"
