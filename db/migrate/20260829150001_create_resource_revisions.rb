class CreateResourceRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_revisions do |t|
      t.references :resource, null: false, foreign_key: true
      t.integer :origin, null: false
      t.string :title, null: false
      t.string :author_name
      t.text :source_excerpt
      t.text :ai_summary
      t.jsonb :key_points, null: false, default: []
      t.jsonb :capabilities, null: false, default: []
      t.string :suggested_category_slug
      t.jsonb :suggested_tag_slugs, null: false, default: []
      t.string :source_fingerprint, null: false
      t.string :summary_basis
      t.integer :summary_status, null: false, default: 0
      t.integer :review_status, null: false, default: 0
      t.string :ai_provider
      t.string :ai_model
      t.string :prompt_version
      t.string :summary_input_sha256
      t.datetime :summary_generated_at
      t.bigint :reviewed_by_id
      t.datetime :reviewed_at
      t.text :rejection_reason

      t.timestamps
    end

    add_index :resource_revisions, [ :resource_id, :source_fingerprint ], unique: true,
      name: "index_resource_revisions_on_resource_and_fingerprint"
    add_index :resource_revisions, [ :review_status, :created_at ]
    add_index :resource_revisions, :reviewed_by_id
  end
end
