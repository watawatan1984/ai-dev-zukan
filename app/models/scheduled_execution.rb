class ScheduledExecution < ApplicationRecord
  enum :status, {
    pending: 0,
    enqueued: 1,
    running: 2,
    succeeded: 3,
    failed: 4
  }, validate: true

  validates :task_name, :scheduled_for, presence: true
  validates :task_name, uniqueness: { scope: :scheduled_for }
end
