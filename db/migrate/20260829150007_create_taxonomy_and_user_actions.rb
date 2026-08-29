class CreateTaxonomyAndUserActions < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :categories, :slug, unique: true

    create_table :tags do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :normalized_name, null: false

      t.timestamps
    end
    add_index :tags, :slug, unique: true
    add_index :tags, :normalized_name, unique: true

    add_reference :resources, :category, foreign_key: true

    create_table :resource_tags do |t|
      t.references :resource, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.integer :origin, null: false, default: 0

      t.timestamps
    end
    add_index :resource_tags, [ :resource_id, :tag_id ], unique: true

    create_table :bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :resource, null: false, foreign_key: true

      t.timestamps
    end
    add_index :bookmarks, [ :user_id, :resource_id ], unique: true

    create_table :hidden_resources do |t|
      t.references :user, null: false, foreign_key: true
      t.references :resource, null: false, foreign_key: true

      t.timestamps
    end
    add_index :hidden_resources, [ :user_id, :resource_id ], unique: true
  end
end
