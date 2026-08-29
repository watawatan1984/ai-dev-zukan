class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_table :resources do |t|
      t.integer :kind, null: false
      t.string :slug, null: false
      t.text :canonical_url, null: false
      t.text :normalized_canonical_url, null: false
      t.integer :source_provider, null: false
      t.string :external_uid
      t.integer :publication_status, null: false, default: 0
      t.datetime :source_published_at
      t.datetime :source_updated_at
      t.bigint :popularity_raw, null: false, default: 0
      t.decimal :popularity_score, precision: 6, scale: 5, null: false, default: 0
      t.datetime :last_synced_at
      t.datetime :published_at
      t.datetime :archived_at

      t.timestamps
    end

    add_index :resources, :slug, unique: true
    add_index :resources, [ :kind, :normalized_canonical_url ], unique: true,
      name: "index_resources_on_kind_and_normalized_url"
    add_index :resources, [ :kind, :source_provider, :external_uid ], unique: true,
      where: "external_uid IS NOT NULL",
      name: "index_resources_on_external_identity"
    add_index :resources, [ :publication_status, :kind, :published_at ]
  end
end
