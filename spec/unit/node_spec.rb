require 'spec_helper'

describe "MongoPercolator::Node unit" do
  before :all do
    class NodeUnitTestNoExports1
      include MongoPercolator::Node
      no_exports
    end

    class NodeUnitTestNoExportsDeclared1
      include MongoPercolator::Node
      key :hidden, String
    end

    class NodeUnitTestExports1
      include MongoPercolator::Node
      key :hidden, String
      key :visible, String
      export 'visible'
      versioned!
    end

    class NodeUnitWithCallbacks
      include MongoPercolator::Node
      key :c, String
      before_save { self.c += " save" }
      before_propagation { self.c += " propagate" }
    end
  end
  
  before(:each) { clean_db }

  it "can tell a node is versioned" do
    expect(NodeUnitTestExports1.versioned?).to be true
    expect(NodeUnitTestExports1.new.versioned?).to be true
    expect(NodeUnitTestExports1.new.version).to be_a(BSON::ObjectId)
  end

  it "is not versioned even when it has a version property" do
    node = NodeUnitTestNoExports1.new
    node['version'] = 'blah'
    expect(node).to_not be_versioned
  end

  it "changes versions on save" do
    obj = NodeUnitTestExports1.new
    old_version = obj.version
    expect(old_version).to be_a(BSON::ObjectId)
    expect(obj.save).to be true
    expect(obj.version).to_not eq(old_version)
    expect(obj.version).to be_a(BSON::ObjectId)
  end

  it "sees no exports on a class without them" do
    expect(NodeUnitTestNoExportsDeclared1.obey_exports?).to be false
    expect(NodeUnitTestNoExports1.obey_exports?).to be true
    expect(NodeUnitTestExports1.obey_exports?).to be true
  end

  it "sees no exports on a class without them from an instance" do
    expect(NodeUnitTestNoExportsDeclared1.new.obey_exports?).to be false
    expect(NodeUnitTestNoExports1.new.obey_exports?).to be true
    expect(NodeUnitTestExports1.new.obey_exports?).to be true
  end

  it "sees an empty list of exports when no_exports is declared" do
     expect(NodeUnitTestNoExports1.exports).to eq([])
    expect(NodeUnitTestNoExports1.obey_exports?).to be true
  end

  it "raises an error if the export arg is not a string" do
    expect {
      class NodeUnitTestExports2
        include MongoPercolator::Node
        export :visible
      end
    }.to raise_error(MongoPercolator::DeclarationError,/string/)
  end

  it "raises an error if an export is declared after no_exports" do
    expect {
      class NodeUnitTestExports3
        include MongoPercolator::Node
        no_exports
        export 'visible'
      end
    }.to raise_error(MongoPercolator::DeclarationError, /declared no_exports/)
  end

  it "raises an error if an no_exports is declared after an export" do
    expect {
      class NodeUnitTestExports4
        include MongoPercolator::Node
        export 'visible'
        no_exports
      end
    }.to raise_error(MongoPercolator::DeclarationError, /Exports already defined/)
  end

  it "can see the defined exports" do
     expect(NodeUnitTestExports1.exports).to eq(['visible'])
  end

  it "reduplicates on find" do
    doc = NodeUnitTestExports1.create!
    duplicates = [doc] * 2
    expect(NodeUnitTestExports1.find(duplicates.collect(&:id)).length).to eq(2)
  end

  it "executes before_propagation callback before before_save" do
    doc = NodeUnitWithCallbacks.new
    doc.c = "start"
    doc.save!
     expect(doc.c).to eq("start propagate save")
  end
end

# END
