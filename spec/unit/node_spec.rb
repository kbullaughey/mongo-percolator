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
    end
  end

  it "sees no exports on a class without them" do
    NodeUnitTestNoExportsDeclared1.obey_exports?.should be_false
    NodeUnitTestNoExports1.obey_exports?.should be_true
    NodeUnitTestExports1.obey_exports?.should be_true
  end

  it "sees no exports on a class without them from an instance" do
    NodeUnitTestNoExportsDeclared1.new.obey_exports?.should be_false
    NodeUnitTestNoExports1.new.obey_exports?.should be_true
    NodeUnitTestExports1.new.obey_exports?.should be_true
  end

  it "sees an empty list of exports when no_exports is declared" do
    NodeUnitTestNoExports1.exports.should == []
    NodeUnitTestNoExports1.obey_exports?.should be_true
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
    NodeUnitTestExports1.exports.should == ['visible']
  end
end

# END
