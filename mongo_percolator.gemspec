# -*- encoding: utf-8 -*-
require File.expand_path('../lib/mongo_percolator/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Kevin Bullaughey"]
  gem.email         = ["kbullaughey@gmail.com"]
  gem.description   = %q{MongoDB-oriented distributed computation framework}
  gem.summary       = %q{Inspired by Google Percolator, but much simpler, written in Ruby, and based on MongoDB and MongoMapper}
  gem.homepage      = ""
  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "mongo_percolator"
  gem.require_paths = ["lib"]
  gem.version       = MongoPercolator::VERSION
  gem.required_ruby_version = '~> 2.4'

  # Dependencies
  gem.add_dependency 'mongo', '~> 1.12.0'
  gem.add_dependency 'bson_ext'
  gem.add_dependency 'mongo_mapper'
  gem.add_dependency 'state_machines'
  gem.add_dependency 'state_machines-activemodel'
  gem.add_dependency 'activemodel', '~> 4.2'
  gem.add_dependency 'activesupport', '~> 4.2'
end
