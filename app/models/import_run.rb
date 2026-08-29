class ImportRun < ApplicationRecord
  enum :status, {
    running: 0,
    succeeded: 1,
    failed: 2
  }, validate: true

  validates :source_name, :started_at, presence: true
  validates :fetched_count, :created_count, :unchanged_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
