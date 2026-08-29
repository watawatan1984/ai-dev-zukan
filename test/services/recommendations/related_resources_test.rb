require "test_helper"

class Recommendations::RelatedResourcesTest < ActiveSupport::TestCase
  test "ranks shared tags and kind with an explainable reason" do
    automation = Tag.create!(name: "Automation", normalized_name: "automation", slug: "automation")
    current = publish_resource(slug: "current-mcp", title: "Current MCP", kind: :mcp)
    related = publish_resource(slug: "related-mcp", title: "Related MCP", kind: :mcp)
    unrelated = publish_resource(slug: "unrelated-article", title: "Unrelated Article", kind: :qiita_article)
    current.tags << automation
    related.tags << automation
    unrelated.update!(popularity_score: 0.99)

    recommendations = Recommendations::RelatedResources.call(resource: current, limit: 2)

    assert_equal related, recommendations.first.resource
    assert_includes recommendations.first.reasons, "Automationタグが共通"
    assert_includes recommendations.first.reasons, "同じMCP"
  end

  private

  def publish_resource(slug:, title:, kind:)
    resource = Resource.create!(
      kind: kind,
      slug: slug,
      canonical_url: "https://example.com/#{slug}",
      normalized_canonical_url: "https://example.com/#{slug}",
      source_provider: :manual
    )
    revision = resource.revisions.create!(
      origin: :manual,
      title: title,
      ai_summary: "テスト用要約",
      source_fingerprint: "#{slug}-v1",
      summary_status: :manually_written,
      review_status: :approved
    )
    resource.publish!(revision:)
    resource
  end
end
