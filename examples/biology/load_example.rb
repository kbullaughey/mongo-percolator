require 'mongo_percolator'

example_root = File.expand_path('..', __FILE__)

example_files = [
  'transcribe_operation',
  'gene',
  'rna',
]

example_files.each {|f| require File.join(example_root, f) }
