#!/usr/bin/env ruby

require 'mongo_percolator'
MongoPercolator.connect

class TimeTest1
  include MongoMapper::Document
  timestamps!
  key :counter, Integer
end

1.upto(10000) do |i|
  TimeTest1.create! :counter => i
end

puts "#{TimeTest1.count} TimeTest1 documents inserted"
