class Resource < ApplicationRecord
  class UnapprovedRevision < StandardError; end
  class ForeignRevision < StandardError; end

  enum :kind, {
    mcp: 0,
    skill: 1,
    zenn_article: 2,
    qiita_article: 3
  }, prefix: true, validate: true

  enum :source_provider, {
    github: 0,
    zenn: 1,
    qiita: 2,
    manual: 3
  }, prefix: true, validate: true

  enum :publication_status, {
    unpublished: 0,
    published: 1,
    archived: 2
  }, validate: true

  has_many :revisions,
    class_name: "ResourceRevision",
    inverse_of: :resource,
    dependent: :restrict_with_exception
  belongs_to :current_revision,
    class_name: "ResourceRevision",
    optional: true
  belongs_to :category, optional: true # legacy rollback relation
  has_many :resource_categories, dependent: :destroy
  has_many :controlled_categories, through: :resource_categories, source: :category
  has_many :resource_tags, dependent: :destroy # legacy rollback relation
  has_many :tags, through: :resource_tags # legacy rollback relation
  has_many :controlled_resource_tags, dependent: :destroy
  has_many :controlled_tags, through: :controlled_resource_tags, source: :tag
  has_many :bookmarks, dependent: :destroy
  has_many :hidden_resource_records, class_name: "HiddenResource", dependent: :destroy

  validates :slug, presence: true, uniqueness: true
  validates :canonical_url, :normalized_canonical_url, presence: true
  validates :normalized_canonical_url, uniqueness: { scope: :kind }
  validates :external_uid,
    uniqueness: { scope: [ :kind, :source_provider ] },
    allow_nil: true
  validate :current_revision_is_approved_and_owned

  scope :publicly_visible, -> { published.where.not(current_revision_id: nil) }

  def publish!(revision:)
    raise ForeignRevision, "Revision must belong to this resource" unless revision.resource_id == id
    raise UnapprovedRevision, "Only an approved revision can be published" unless revision.approved?

    transaction do
      update!(
        current_revision: revision,
        publication_status: :published,
        published_at: published_at || Time.current,
        archived_at: nil,
        search_text: Search::Normalize.call([
          revision.title,
          revision.author_name,
          revision.ai_summary,
          category&.name,
          tags.pluck(:name)
        ].compact.join(" "))
      )
    end
  end

  private

  def current_revision_is_approved_and_owned
    return unless current_revision

    errors.add(:current_revision, "must belong to this resource") if current_revision.resource_id != id
    errors.add(:current_revision, "must be approved") unless current_revision.approved?
  end
end
