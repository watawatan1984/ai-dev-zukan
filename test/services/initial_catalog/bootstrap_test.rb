require "test_helper"

class InitialCatalog::BootstrapTest < ActiveSupport::TestCase
  FakeCatalog = Struct.new(:snapshots) do
    def fetch(limit:)
      snapshots.first(limit)
    end
  end

  class FakeSummarizer
    def call(title:, source_excerpt:)
      Ai::Summary.new(
        summary: "#{title}の要約",
        capabilities: [ source_excerpt ],
        key_points: [],
        suggested_category_slug: "developer-tools",
        suggested_tag_slugs: [ "bootstrap" ],
        provider: "test",
        model: "test-model",
        prompt_version: "test-v1",
        basis: "fixture"
      )
    end
  end

  test "imports and summarizes the requested count without auto publishing" do
    catalogs = InitialCatalog::Bootstrap::SOURCE_KINDS.to_h do |source_name, kind|
      snapshots = 2.times.map { |index| snapshot(source_name:, kind:, index:) }
      [ source_name, FakeCatalog.new(snapshots) ]
    end

    result = InitialCatalog::Bootstrap.call(
      limit: 2,
      catalogs: catalogs,
      summarizer_factory: -> { FakeSummarizer.new },
      concurrency: 1,
      sleeper: ->(*) { }
    )

    assert result.complete?
    assert_equal 2, result.counts.dig("mcp", :summarized)
    assert_equal 2, result.counts.dig("skill", :summarized)
    assert_equal 2, result.counts.dig("zenn_article", :summarized)
    assert_equal 2, result.counts.dig("qiita_article", :summarized)
    assert_equal 8, ResourceRevision.review_pending.count
    assert_equal 0, Resource.published.count
  end

  test "summarizes a newer revision even when an older revision already succeeded" do
    resource = Resource.create!(
      kind: :mcp,
      slug: "updated-mcp",
      canonical_url: "https://example.com/updated-mcp",
      normalized_canonical_url: "https://example.com/updated-mcp",
      source_provider: :github,
      external_uid: "example/updated-mcp"
    )
    resource.revisions.create!(
      origin: :imported,
      title: "Old MCP",
      source_excerpt: "old excerpt",
      source_fingerprint: "old",
      ai_summary: "古い要約です。",
      summary_status: :succeeded,
      review_status: :review_pending
    )
    latest = resource.revisions.create!(
      origin: :imported,
      title: "Updated MCP",
      source_excerpt: "new excerpt",
      source_fingerprint: "new",
      summary_status: :queued,
      review_status: :draft
    )

    InitialCatalog::Bootstrap.call(
      limit: 1,
      import_sources: false,
      summarizer_factory: -> { FakeSummarizer.new },
      concurrency: 1,
      sleeper: ->(*) { }
    )

    assert_predicate latest.reload, :summary_status_succeeded?
    assert_predicate latest, :review_pending?
  end

  private

  def snapshot(source_name:, kind:, index:)
    provider = source_name.start_with?("github") ? :github : source_name.to_sym
    uid = "#{source_name}-#{index}"
    Sources::Snapshot.new(
      kind: kind,
      provider: provider,
      external_uid: uid,
      canonical_url: "https://example.com/#{uid}",
      title: "#{source_name} #{index}",
      author_name: "example",
      excerpt: "source excerpt #{index}",
      source_fingerprint: "fingerprint-#{uid}",
      source_published_at: Time.zone.local(2026, 8, 1),
      source_updated_at: Time.zone.local(2026, 8, 2),
      popularity_raw: index
    )
  end
end
