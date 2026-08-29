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
      summary_status: :succeeded,
      review_status: :review_pending
    )

    result = Editorial::ApproveAndPublish.call(revision: revision, reviewer: admin)

    assert_equal resource, result
    assert_predicate revision.reload, :approved?
    assert_equal admin, revision.reviewer
    assert_equal revision, resource.reload.current_revision
    assert_predicate resource, :published?
    assert_equal 1, AdminAuditLog.where(
      actor: admin,
      auditable: revision,
      action: "resource_revision.approve_and_publish"
    ).count
  end
end
