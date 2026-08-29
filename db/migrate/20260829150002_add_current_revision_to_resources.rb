class AddCurrentRevisionToResources < ActiveRecord::Migration[8.1]
  def change
    add_reference :resources, :current_revision,
      foreign_key: { to_table: :resource_revisions },
      index: { unique: true }
  end
end
