require File.dirname(__FILE__) + '/helper.rb'

# ATOMICS_CONFIG = YAML.load_file("atomics.yml")

ATOMICS_CONFIG = {
  'my_type' => {
    'host' => 'orb-atomics.ops.aol.com',
    'port' => '8080',
    'path' => '/jAtomics/select/?version=1'
  }
}

module AtomicsResource
  describe Base do
    before :each do
      class MyTest < AtomicsResource::Base
        set_atomics_type :my_type
        set_table_name   :my_table
        set_primary_key  :my_pk
      end
    end

    context "class variables" do
      it "should have class settings" do
        MyTest.atomics_type.should == :my_type
        MyTest.table_name.should   == :my_table
        MyTest.primary_key.should  == :my_pk
      end
    end

    context "atomics config" do
      require 'uri'
      it "should create a valid base URL" do
        sql = "select * from foo where bar = 'wibble'"
        URI.parse(MyTest.construct_url_for_sql(sql)).class.should == URI::HTTP
      end
    end

    context "sql construction" do
      it "should construct sql from array conditions" do
        a = MyTest.construct_sql_for_conditions(["foo = \? AND bar = \?", :hello, :world])
        a.should == "foo = 'hello' AND bar = 'world'"
      end
      it "should contruct sql from hash conditions" do
        b = MyTest.construct_sql_for_conditions({:foo => :hello, :bar => :world})
        b.should == "foo='hello' AND bar='world'"
      end
    end

  end

end
