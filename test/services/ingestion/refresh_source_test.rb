require "test_helper"

class Ingestion::RefreshSourceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  FakeCatalog = Struct.new(:snapshots) do
    def fetch(limit:)
      snapshots.first(limit)
    end
  end

  test "records fetched, created, and unchanged counts for operation evidence" do
    snapshot = Sources::Snapshot.new(
      kind: :mcp,
      provider: :github,
      external_uid: "example/observable-mcp",
      canonical_url: "https://github.com/example/observable-mcp",
      title: "Observable MCP",
      author_name: "example",
      excerpt: "運用状況を確認できます。",
      source_fingerprint: "observable-v1",
      source_published_at: Time.zone.local(2026, 1, 1),
      source_updated_at: Time.zone.local(2026, 8, 1),
      popularity_raw: 10
    )
    catalog = FakeCatalog.new([ snapshot, snapshot ])

    assert_enqueued_jobs 1, only: SummarizeRevisionJob do
      run = Ingestion::RefreshSource.call(source_name: "github_mcp", catalog:, limit: 10)

      assert run.succeeded?
      assert_equal 2, run.fetched_count
      assert_equal 1, run.created_count
      assert_equal 1, run.unchanged_count
      assert run.completed_at.present?
    end
  end
end
