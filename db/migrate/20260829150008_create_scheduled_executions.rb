class CreateScheduledExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_executions do |t|
      t.string :task_name, null: false
      t.datetime :scheduled_for, null: false
      t.integer :status, null: false, default: 0
      t.string :active_job_id
      t.text :error_message
      t.datetime :completed_at

      t.timestamps
    end

    add_index :scheduled_executions, [ :task_name, :scheduled_for ], unique: true
    add_index :scheduled_executions, [ :status, :scheduled_for ]
  end
end
