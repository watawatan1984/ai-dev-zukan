require "test_helper"

class Editorial::ApproveAndPublishTest < ActiveSupport::TestCase
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
      suggested_category_slug: "ruby-on-rails",
      suggested_tag_slugs: [ "background-jobs", "solid-queue" ],
      summary_status: :succeeded,
      review_status: :review_pending
    )

    result = Editorial::ApproveAndPublish.call(revision: revision, reviewer: admin)

    assert_equal resource, result
    assert_predicate revision.reload, :approved?
    assert_equal admin, revision.reviewer
    assert_equal revision, resource.reload.current_revision
    assert_predicate resource, :published?
    assert_equal "ruby-on-rails", resource.category.slug
    assert_equal %w[background-jobs solid-queue], resource.tags.order(:slug).pluck(:slug)
    assert_equal %w[ai ai], resource.resource_tags.order(:id).pluck(:origin)
    assert_includes resource.search_text, "ruby on rails"
    assert_includes resource.search_text, "solid queue"
    assert_equal 1, AdminAuditLog.where(
      actor: admin,
      auditable: revision,
      action: "resource_revision.approve_and_publish"
    ).count
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
