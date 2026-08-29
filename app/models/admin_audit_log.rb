class AdminAuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User"
  belongs_to :auditable, polymorphic: true

  validates :action, presence: true
end
