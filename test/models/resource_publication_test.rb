require "test_helper"

class ResourcePublicationTest < ActiveSupport::TestCase
  test "review pending revision cannot become the published revision" do
    resource = Resource.create!(
      kind: :mcp,
      slug: "example-mcp",
      canonical_url: "https://github.com/example/mcp",
      normalized_canonical_url: "https://github.com/example/mcp",
      source_provider: :github,
      external_uid: "example/mcp"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Example MCP",
      source_fingerprint: "pending-fingerprint",
      summary_status: :succeeded,
      review_status: :review_pending
    )

    error = assert_raises(Resource::UnapprovedRevision) do
      resource.publish!(revision: revision)
    end

    assert_equal "Only an approved revision can be published", error.message
    assert_predicate resource.reload, :unpublished?
    assert_nil resource.current_revision
  end

  test "approved revision becomes the current published revision" do
    resource = Resource.create!(
      kind: :skill,
      slug: "example-skill",
      canonical_url: "https://github.com/example/skills/tree/main/example",
      normalized_canonical_url: "https://github.com/example/skills/tree/main/example",
      source_provider: :github,
      external_uid: "example/skills:example"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Example Skill",
      source_fingerprint: "approved-fingerprint",
      summary_status: :succeeded,
      review_status: :approved
    )

    resource.publish!(revision: revision)

    assert_predicate resource.reload, :published?
    assert_equal revision, resource.current_revision
    assert_not_nil resource.published_at
  end

  test "approved revision content is immutable" do
    resource = Resource.create!(
      kind: :mcp,
      slug: "immutable-mcp",
      canonical_url: "https://github.com/example/immutable-mcp",
      normalized_canonical_url: "https://github.com/example/immutable-mcp",
      source_provider: :github,
      external_uid: "example/immutable-mcp"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Approved title",
      source_fingerprint: "immutable-fingerprint",
      summary_status: :succeeded,
      review_status: :approved
    )

    assert_not revision.update(title: "Changed without a new revision", review_status: :review_pending)
    assert_includes revision.errors[:base], "Approved revisions are immutable"
    assert_equal "Approved title", revision.reload.title
    assert_predicate revision, :approved?
  end
end
