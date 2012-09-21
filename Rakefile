#!/usr/bin/env rake
require "bundler/gem_tasks"
Dir["./tasks/*.rb"].each {|f| require f }

task :pry do
  sh "bundle exec pry -r './scripts/pry_setup.rb'"
end
