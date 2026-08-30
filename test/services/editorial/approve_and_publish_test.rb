require "test_helper"

class Editorial::ApproveAndPublishTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "admin approval publishes the revision and records an audit log" do
    admin = users(:admin)
    resource = Resource.create!(
      kind: :qiita_article,
      slug: "rails-background-jobs",
      canonical_url: "https://qiita.com/example/items/123",
      normalized_canonical_url: "https://qiita.com/example/items/123",
      source_provider: :qiita,
      external_uid: "123"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Railsのバックグラウンドジョブ",
      source_fingerprint: "qiita-123-v1",
      ai_summary: "Solid Queueを使った非同期処理を解説する記事です。",
      suggested_category_slugs: [ "coding-development", "testing-quality" ],
      suggested_tag_slugs: [ "ruby-on-rails", "testing" ],
      taxonomy_origin: :admin,
      summary_status: :succeeded,
      review_status: :review_pending
    )

    result = Editorial::ApproveAndPublish.call(revision: revision, reviewer: admin)

    assert_equal resource, result
    assert_predicate revision.reload, :approved?
    assert_equal admin, revision.reviewer
    assert_equal revision, resource.reload.current_revision
    assert_predicate resource, :published?
    assert_empty resource.resource_tags
    assert_nil resource.category
    assert_equal %w[coding-development testing-quality], resource.controlled_categories.order(:slug).pluck(:slug)
    assert_equal %w[ruby-on-rails testing], resource.controlled_tags.order(:slug).pluck(:slug)
    assert_equal %w[admin admin], resource.controlled_resource_tags.order(:id).pluck(:origin)
    assert_includes resource.search_text, "コード作成・開発支援"
    assert_includes resource.search_text, "ruby on rails"
    audit_log = AdminAuditLog.find_by!(
      actor: admin,
      auditable: revision,
      action: "resource_revision.approve_and_publish"
    )
    assert_equal [ "review_pending", "approved" ], audit_log.changeset.fetch("review_status")
    assert_equal resource.id, audit_log.changeset.fetch("resource_id")
    assert_equal [ [], resource.controlled_category_ids.sort ], audit_log.changeset.fetch("controlled_category_ids")
    assert_equal [ [], resource.controlled_tag_ids.sort ], audit_log.changeset.fetch("controlled_tag_ids")
  end

  test "repeating approval does not mutate the approved revision" do
    admin = users(:admin)
    resource = Resource.create!(
      kind: :skill,
      slug: "repeatable-approval",
      canonical_url: "https://github.com/example/repeatable-approval",
      normalized_canonical_url: "https://github.com/example/repeatable-approval",
      source_provider: :github,
      external_uid: "example/repeatable-approval"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Repeatable approval",
      source_fingerprint: "repeatable-approval-v1",
      ai_summary: "再試行可能な承認処理です。",
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "ruby", "testing" ],
      summary_status: :succeeded,
      review_status: :review_pending
    )

    Editorial::ApproveAndPublish.call(revision: revision, reviewer: admin)

    assert_nothing_raised do
      Editorial::ApproveAndPublish.call(revision: revision.reload, reviewer: admin)
    end
    assert_equal revision, resource.reload.current_revision
    assert_predicate revision.reload, :approved?
  end

  test "invalid taxonomy cannot become approved or change publication state" do
    admin = users(:admin)
    legacy_category = Category.create!(slug: "legacy-category", name: "Legacy Category")
    legacy_tag = Tag.create!(slug: "legacy-tag", name: "Legacy Tag", normalized_name: "legacy-tag")
    resource = Resource.create!(
      kind: :mcp,
      slug: "invalid-taxonomy-approval",
      canonical_url: "https://github.com/example/invalid-taxonomy-approval",
      normalized_canonical_url: "https://github.com/example/invalid-taxonomy-approval",
      source_provider: :github,
      external_uid: "example/invalid-taxonomy-approval",
      category: legacy_category
    )
    ResourceTag.create!(resource:, tag: legacy_tag, origin: :source)
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Invalid taxonomy approval",
      source_fingerprint: "invalid-taxonomy-approval-v1",
      ai_summary: "Invalid taxonomy must stop approval.",
      suggested_category_slugs: [ "unknown" ],
      suggested_tag_slugs: [ "mcp", "mcp" ],
      summary_status: :succeeded,
      review_status: :review_pending
    )

    assert_raises(Taxonomy::ApplyRevision::InvalidSuggestion) do
      Editorial::ApproveAndPublish.call(revision: revision, reviewer: admin)
    end

    assert_predicate revision.reload, :review_pending?
    assert_predicate resource.reload, :unpublished?
    assert_nil resource.current_revision
    assert_equal legacy_category, resource.category
    assert_equal [ legacy_tag ], resource.tags.to_a
    assert_empty resource.controlled_categories
    assert_empty resource.controlled_tags
    assert_empty resource.search_text
    assert_equal 0, AdminAuditLog.where(auditable: revision).count
  end

  test "draft without a summary cannot be approved" do
    admin = users(:admin)
    resource = Resource.create!(
      kind: :mcp,
      slug: "summary-not-ready",
      canonical_url: "https://github.com/example/summary-not-ready",
      normalized_canonical_url: "https://github.com/example/summary-not-ready",
      source_provider: :github,
      external_uid: "example/summary-not-ready"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Summary not ready",
      source_fingerprint: "summary-not-ready-v1",
      summary_status: :queued,
      review_status: :draft
    )

    assert_raises(Editorial::ApproveAndPublish::RevisionNotReady) do
      Editorial::ApproveAndPublish.call(revision: revision, reviewer: admin)
    end
    assert_predicate resource.reload, :unpublished?
    assert_predicate revision.reload, :draft?
  end
end
