require "test_helper"

class Ingestion::UpsertSnapshotTest < ActiveSupport::TestCase
  test "changed source creates a review candidate without replacing the published revision" do
    resource = Resource.create!(
      kind: :mcp,
      slug: "example-mcp",
      canonical_url: "https://github.com/example/mcp",
      normalized_canonical_url: "https://github.com/example/mcp",
      source_provider: :github,
      external_uid: "example/mcp"
    )
    published_revision = resource.revisions.create!(
      origin: :imported,
      title: "Example MCP v1",
      source_fingerprint: "fingerprint-v1",
      summary_status: :succeeded,
      review_status: :approved
    )
    resource.publish!(revision: published_revision)

    snapshot = Sources::Snapshot.new(
      kind: :mcp,
      provider: :github,
      external_uid: "example/mcp",
      canonical_url: "https://github.com/example/mcp",
      title: "Example MCP v2",
      author_name: "example",
      excerpt: "Updated source description",
      source_fingerprint: "fingerprint-v2",
      source_published_at: 2.years.ago,
      source_updated_at: Time.current,
      popularity_raw: 120
    )

    result = Ingestion::UpsertSnapshot.call(snapshot: snapshot)

    assert_equal :created_revision, result.status
    assert_equal published_revision, resource.reload.current_revision
    assert_predicate resource, :published?
    assert_equal "Example MCP v2", result.revision.title
    assert_predicate result.revision, :summary_status_queued?
    assert_predicate result.revision, :draft?
  end

  test "automatic import adopts a manually registered resource with the same canonical URL" do
    manual = Resource.create!(
      kind: :skill,
      slug: "manual-skill",
      canonical_url: "https://github.com/example/manual-skill/",
      normalized_canonical_url: "https://github.com/example/manual-skill",
      source_provider: :manual
    )
    snapshot = Sources::Snapshot.new(
      kind: :skill,
      provider: :github,
      external_uid: "example/manual-skill",
      canonical_url: "https://github.com/example/manual-skill",
      title: "Manual Skill",
      author_name: "example",
      excerpt: "README excerpt",
      source_fingerprint: "manual-skill-v1",
      source_published_at: 1.year.ago,
      source_updated_at: Time.current,
      popularity_raw: 5
    )

    result = nil
    assert_no_difference "Resource.count" do
      result = Ingestion::UpsertSnapshot.call(snapshot:)
    end

    assert_equal manual, result.resource
    assert_predicate manual.reload, :source_provider_github?
    assert_equal "example/manual-skill", manual.external_uid
  end
end
