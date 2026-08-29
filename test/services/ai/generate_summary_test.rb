require "test_helper"

class Ai::GenerateSummaryTest < ActiveSupport::TestCase
  FakeSummarizer = Struct.new(:result) do
    def call(title:, source_excerpt:)
      raise "missing title" if title.blank?
      raise "missing source excerpt" if source_excerpt.blank?

      result
    end
  end

  test "stores structured AI output and moves the revision to review pending" do
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
      source_excerpt: "GitHubのIssueを検索して一覧化します。",
      source_fingerprint: "example-v1",
      summary_status: :queued,
      review_status: :draft
    )
    result = Ai::Summary.new(
      summary: "GitHub Issueの調査を効率化するMCPです。",
      capabilities: [ "Issue検索", "一覧化" ],
      key_points: [ "GitHubトークンが必要" ],
      suggested_category_slug: "developer-tools",
      suggested_tag_slugs: [ "github", "mcp" ],
      provider: "nvidia",
      model: "test-model",
      prompt_version: "v1",
      basis: "README excerpt"
    )

    Ai::GenerateSummary.call(revision: revision, summarizer: FakeSummarizer.new(result))

    revision.reload
    assert revision.summary_status_succeeded?
    assert revision.review_pending?
    assert_equal result.summary, revision.ai_summary
    assert_equal result.capabilities, revision.capabilities
    assert_equal result.key_points, revision.key_points
    assert_equal "nvidia", revision.ai_provider
    assert_equal "test-model", revision.ai_model
    assert revision.summary_generated_at.present?
  end

  test "marks a revision as failed when the provider raises" do
    resource = Resource.create!(
      kind: :skill,
      slug: "broken-skill",
      canonical_url: "https://github.com/example/broken-skill",
      normalized_canonical_url: "https://github.com/example/broken-skill",
      source_provider: :github,
      external_uid: "example/broken-skill"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Broken Skill",
      source_excerpt: "要約対象です。",
      source_fingerprint: "broken-v1",
      summary_status: :queued,
      review_status: :draft
    )
    failing = Class.new do
      def call(**)
        raise Faraday::TimeoutError, "provider timeout"
      end
    end.new

    assert_raises(Faraday::TimeoutError) do
      Ai::GenerateSummary.call(revision: revision, summarizer: failing)
    end

    assert revision.reload.summary_status_failed?
    assert revision.draft?
  end
end
