require "test_helper"

class InitialCatalog::ArchiveIrrelevantMcpTest < ActiveSupport::TestCase
  FakeCatalog = Struct.new(:snapshots) do
    def fetch(limit:)
      snapshots.first(limit)
    end
  end

  test "archives adjacent tools while preserving explicit MCP server repositories" do
    adjacent = create_mcp(title: "gemini-cli", uid: "google-gemini/gemini-cli")
    server = create_mcp(title: "github-mcp-server", uid: "github/github-mcp-server")
    server.update!(publication_status: :archived, archived_at: Time.current)
    catalog = FakeCatalog.new([ snapshot_for(server) ])

    result = InitialCatalog::ArchiveIrrelevantMcp.call(catalog:, limit: 1)

    assert_equal 1, result.selected_count
    assert_includes result.reactivated_ids, server.id
    assert_includes result.archived_ids, adjacent.id
    assert_predicate adjacent.reload, :archived?
    assert_predicate server.reload, :unpublished?
  end

  test "does not archive anything when the selected set is below target" do
    adjacent = create_mcp(title: "gemini-cli", uid: "google-gemini/gemini-cli")
    catalog = FakeCatalog.new([])

    assert_raises(InitialCatalog::ArchiveIrrelevantMcp::IncompleteSelection) do
      InitialCatalog::ArchiveIrrelevantMcp.call(catalog:, limit: 1)
    end
    assert_predicate adjacent.reload, :unpublished?
  end

  private

  def create_mcp(title:, uid:)
    resource = Resource.create!(
      kind: :mcp,
      slug: title,
      canonical_url: "https://github.com/#{uid}",
      normalized_canonical_url: "https://github.com/#{uid}",
      source_provider: :github,
      external_uid: uid
    )
    resource.revisions.create!(
      origin: :imported,
      title: title,
      source_excerpt: "source excerpt",
      source_fingerprint: "fingerprint-#{title}",
      ai_summary: "日本語の要約です。",
      summary_status: :succeeded,
      review_status: :review_pending
    )
    resource
  end


  def snapshot_for(resource)
    Sources::Snapshot.new(
      kind: :mcp,
      provider: :github,
      external_uid: resource.external_uid,
      canonical_url: resource.canonical_url,
      title: resource.revisions.first.title,
      author_name: "example",
      excerpt: resource.revisions.first.source_excerpt,
      source_fingerprint: "selected",
      source_published_at: Time.current,
      source_updated_at: Time.current,
      popularity_raw: 1
    )
  end
end
