class CreateImportRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :import_runs do |t|
      t.string :source_name, null: false
      t.integer :status, null: false, default: 0
      t.integer :fetched_count, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :unchanged_count, null: false, default: 0
      t.text :error_message
      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :import_runs, [ :source_name, :started_at ]
    add_index :import_runs, [ :status, :started_at ]
  end
end
