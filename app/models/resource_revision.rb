class ResourceRevision < ApplicationRecord
  enum :origin, {
    manual: 0,
    imported: 1
  }, prefix: true, validate: true

  enum :summary_status, {
    not_requested: 0,
    queued: 1,
    processing: 2,
    succeeded: 3,
    failed: 4,
    manually_written: 5
  }, prefix: true, validate: true

  enum :review_status, {
    draft: 0,
    review_pending: 1,
    approved: 2,
    rejected: 3
  }, validate: true

  enum :taxonomy_status, {
    not_requested: 0,
    queued: 1,
    processing: 2,
    succeeded: 3,
    failed: 4
  }, prefix: true, validate: true

  enum :taxonomy_origin, {
    source: 0,
    ai: 1,
    admin: 2
  }, prefix: true, validate: true

  belongs_to :resource, inverse_of: :revisions
  belongs_to :reviewer,
    class_name: "User",
    foreign_key: :reviewed_by_id,
    optional: true

  validates :title, :source_fingerprint, presence: true
  validates :source_fingerprint, uniqueness: { scope: :resource_id }
  validate :approved_revision_is_immutable, on: :update

  def effective_suggested_category_slugs
    Array(suggested_category_slugs).presence || Array(suggested_category_slug).compact
  end

  private

  def approved_revision_is_immutable
    return unless review_status_in_database == "approved"

    errors.add(:base, "Approved revisions are immutable")
  end
end
