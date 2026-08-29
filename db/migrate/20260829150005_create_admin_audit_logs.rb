class CreateAdminAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audit_logs do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :auditable, polymorphic: true, null: false
      t.string :action, null: false
      t.jsonb :changeset, null: false, default: {}
      t.string :request_id

      t.timestamps
    end

    add_index :admin_audit_logs, [ :action, :created_at ]
  end
end
