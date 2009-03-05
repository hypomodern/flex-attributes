ActiveRecord::Schema.define(:version => 0) do
  create_table :test_dummies, :force => true do |t|
    t.column :name, :string
  end
  create_table :test_dummy_attributes, :force => true, :id => false do |t|
    t.column :name, :string
    t.column :value, :string
    t.column :test_dummy_id, :integer
  end
  
  create_table :wiki_articles, :force => true do |t|
    t.column :name, :string
    t.column :version, :integer, :default => 1, :null => false
  end
  
  create_table :wiki_article_attributes, :force => true, :id => false do |t|
    t.column :name, :string
    t.column :value, :string
    t.column :wiki_article_id, :integer
    t.column :wiki_article_version, :integer
  end
  
  create_table :capitols, :force => true do |t|
    t.column :name, :string
  end
  create_table :capitol_attributes, :force => true, :id => false do |t|
    t.column :name, :string
    t.column :value, :string
    t.column :test_dummy_id, :integer
  end
end
