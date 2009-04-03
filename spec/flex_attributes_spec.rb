require File.dirname(__FILE__) + '/spec_helper'

describe "Hypomodern::FlexAttributes" do
  before(:each) do
    # create a faux-model to bring to this testin' rodeo
    class TestDummy < ActiveRecord::Base
    end
    class WikiArticle < ActiveRecord::Base
    end
  end
  
  describe "successful inclusion" do
    it "should add the helpful `has_flex_attributes` macro to any class that includes it" do
      TestDummy.should respond_to(:has_flex_attributes)
    end
  end
  
  describe "has_flex_attributes" do
    before(:each) do
      TestDummy.class_eval do
        has_flex_attributes
      end
      
      @london = TestDummy.new
    end
    it "should accept a hash of options, with some default values" do
      @london.flex_options.should be_a_kind_of(Hash)
    end
    it "should make these options available to the base class" do
      @london.flex_options[:class_name].should == 'TestDummyAttribute'
      @london.flex_options[:name_field].should == "name"
    end
    it "should then include the InstanceMethods into the base class" do
      @london.should respond_to(:flex_attributes)
      @london.class.private_method_defined?(:save_flex_attributes).should be_true
    end
  end
  
  describe "basic model behavior" do
    before(:each) do
      @paris = TestDummy.new
    end
    it "should permit the saving of arbitrary fields by default" do
      @paris.flex_attributes.should be_nil # meaning anything should be ok.
      lambda { @paris.brie_and_cheese = true }.should_not raise_error
    end
    it "should save the flex_attributes when the model itself is saved" do
      @paris.name = "Paris"
      @paris.has_brie_and_cheese = true
      
      @paris.save.should be_true
      @paris.has_brie_and_cheese.should be_true
    end
    it "should correctly handle multiple attributes" do
      @paris.name = "Paris"
      @paris.has_brie_and_cheese = true
      @paris.has_worlds_largest_erector_set_monument = true
      @paris.is_smug = true
      
      @paris.save.should be_true
      @paris.has_brie_and_cheese.should be_true
      @paris.has_worlds_largest_erector_set_monument.should be_true
      @paris.is_smug.should be_true
    end
    it "should raise NoMethodError correctly if the attributes are limited" do
      @paris.instance_eval do
        def flex_attributes
          [:has_brie_and_cheese, :is_smug, :has_worlds_largest_erector_set_monument]
        end
      end
      lambda { @paris.trains_on_time }.should raise_error(NoMethodError)
    end
  end # / basics
  
  describe "flex_attributes should be value-attributes" do
    before(:each) do
      @paris = TestDummy.new
      @paris.is_smug = true
      @paris.save
      @paris.is_smug.should be_true
    end
    it "should destroy any previously existing attributes on save" do
      @paris.is_smug = false
      @paris.has_brie_and_cheese = true
      
      TestDummyAttribute.should_receive(:delete_all).with("test_dummy_id = 1")
      @paris.save
      @paris.has_brie_and_cheese.should be_true
    end
    it "should recreate the attributes by default" do
      @paris.save
      @paris.is_smug.should be_true
    end
    it "should purge attributes if instructed to do so" do
      @paris.purge_old_attributes
      @paris.save
      @paris.is_smug.should be_nil
    end
  end
  
  describe "flex_attributes with versioned models" do
    before(:each) do
      WikiArticle.class_eval do
        has_flex_attributes :versioned => true
      end
      
      @wiki_article = WikiArticle.create(:name => "Visiting Zagreb")
      @wiki_article.cold_fusion_invented_at = 14.years.ago
      @wiki_article.save
    end
    
    it "should obtain attributes relating to the model's version" do
      @wiki_article.cold_fusion_invented_at.should_not be_nil
    end
    it "should obtain only those attributes which correspond to the related model's version" do
      @wiki_article.version = 2
      @wiki_article.cold_fusion_invented_at = "Never"
      @wiki_article.save
      
      @wiki_article.cold_fusion_invented_at.should == "Never"
      
      WikiArticleAttribute.all(:conditions => "wiki_article_id = #{@wiki_article.id}").length.should == 2
    end
    it "should not delete flex_attributes of any other versions" do
      @wiki_article.version = 2
      @wiki_article.cold_fusion_invented_at = "Never"
      @wiki_article.save
      
      @wiki_article.cold_fusion_invented_at.should == "Never"
      @wiki_article.version = 1
      @wiki_article.cold_fusion_invented_at.should_not == "Never"
    end
    it "should not create flex_attributes for any other version" do
      @wiki_article.version = 2
      @wiki_article.cold_fusion_invented_at = "Never"
      @wiki_article.save
      
      WikiArticleAttribute.all(:conditions => "version <> 2").length.should == 1
    end
  end
  
  describe "write_extended_attributes" do
    before(:each) do
      class Capitol < ActiveRecord::Base
        attr_accessor :varga
        include Hypomodern::FlexAttributes
        has_flex_attributes({
          :fields => [ "potions", "fury", "weave" ]
        })
      end
      
      Capitol.class_eval do
        attr_accessor :potions, :fury, :weave
      end
      
      @belgrade = Capitol.new
      @belgrade.varga = "cold, snowy"
    end
    it "should assign values based on the passed-in-hash" do
      @belgrade.write_extended_attributes({
        :potions => "none", :fury => 0, :weave => "supreme"
      })
      @belgrade.potions.should == "none"
      @belgrade.fury.should == 0
      @belgrade.weave.should == "supreme"
    end
    it "should only assign values to extended_attributes" do
      @belgrade.write_extended_attributes({:varga => "warm, mild"})
      @belgrade.varga.should == "cold, snowy"
    end
  end
  
end # /specs