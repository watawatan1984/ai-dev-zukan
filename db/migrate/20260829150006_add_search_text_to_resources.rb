class AddSearchTextToResources < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
    add_column :resources, :search_text, :text, null: false, default: ""
    add_index :resources, :search_text, using: :gin, opclass: :gin_trgm_ops
  end
end
