class CreateControlledTaxonomy < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_categories do |t|
      t.references :resource, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.integer :origin, null: false, default: 0
      t.timestamps
    end
    add_index :resource_categories, [ :resource_id, :category_id ], unique: true

    create_table :controlled_resource_tags do |t|
      t.references :resource, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.integer :origin, null: false, default: 0
      t.timestamps
    end
    add_index :controlled_resource_tags, [ :resource_id, :tag_id ], unique: true

    create_table :tag_aliases do |t|
      t.references :tag, null: false, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.timestamps
    end
    add_index :tag_aliases, :normalized_name, unique: true

    change_table :tags, bulk: true do |t|
      t.string :vocabulary_group
      t.boolean :active, null: false, default: false
      t.boolean :filterable, null: false, default: false
      t.integer :position, null: false, default: 0
    end

    add_index :categories, [ :active, :position ]
    add_index :tags, [ :active, :filterable, :vocabulary_group, :position ], name: "index_tags_on_visibility_group_and_position"

    change_table :resource_revisions, bulk: true do |t|
      t.jsonb :suggested_category_slugs, null: false, default: []
      t.jsonb :search_keywords, null: false, default: []
      t.integer :taxonomy_status, null: false, default: 0
      t.integer :taxonomy_origin, null: false, default: 1
      t.string :taxonomy_provider
      t.string :taxonomy_model
      t.string :taxonomy_prompt_version
      t.string :taxonomy_input_sha256
      t.datetime :taxonomy_generated_at
      t.decimal :taxonomy_confidence, precision: 4, scale: 3
    end

    add_index :resource_revisions, [ :taxonomy_status, :created_at ]
  end
end
