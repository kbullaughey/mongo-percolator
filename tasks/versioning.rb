# Code for managing version
def version_triplet
  MongoPercolator::VERSION.split(".").collect{|x| x.to_i}
end

# Takes an array of three integers to add to VERSION and three integers to multiply to VERSION
def bump(by,reset)
  version_triplet.zip(by, reset).collect{|x,y,z| (x+y)*z}.join(".")
end

def bump_patch
  bump([0,0,1], [1,1,1])
end

def bump_minor
  bump([0,1,0], [1,1,0])
end

def bump_major
  bump([1,0,0], [1,0,0])
end

def write_version(v)
  file = File.expand_path('../../lib/mongo_percolator/version.rb', __FILE__)
  lines = File.open(file, "r") {|fp| fp.readlines}
  content = lines.collect{|line| line.sub /VERSION = ".*"/, "VERSION = \"#{v}\""}.join("")
  File.open(file, "w") {|fp| fp.write content }
  puts v
end

def commit_version(v)
  sh "git add lib/mongo_percolator/version.rb"
  sh "git commit lib/mongo_percolator/version.rb"
  sh "git tag -a 'v#{v}' -m 'Version bump to #{v}'"
end

desc "Show version"
task :version do
  puts MongoPercolator::VERSION
end

namespace :version do
  desc "Shorthand for version:bump:patch"
  task :bump => ['version:bump:patch']
  namespace :bump do
    desc "Bump the patch verion number"
    task :patch do
      new_version = bump_patch
      write_version(new_version)
      commit_version(new_version)
    end
    desc "Bump the minor verion number"
    task :minor do
      new_version = bump_minor
      write_version(new_version)
      commit_version(new_version)
    end
    desc "Bump the major verion number"
    task :major do
      new_version = bump_major
      write_version(new_version)
      commit_version(new_version)
    end
  end
end

