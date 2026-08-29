require "test_helper"

class PublicDiscoveryTest < ActionDispatch::IntegrationTest
  test "search page shows only published resources matching the query" do
    matching = publish_resource(
      slug: "gamma-mcp",
      title: "Gamma MCP",
      summary: "GitHub操作を支援します。"
    )
    publish_resource(
      slug: "alpha-skill",
      title: "Alpha Skill",
      summary: "ドキュメント作成を支援します。"
    )

    get resources_path, params: { q: "Gamma" }

    assert_response :success
    assert_select "h2", text: matching.current_revision.title
    assert_select "h2", text: "Alpha Skill", count: 0
    assert_select "[data-controller='theme']"
    assert_select "form[role='search']"
  end

  private

  def publish_resource(slug:, title:, summary:)
    resource = Resource.create!(
      kind: :mcp,
      slug: slug,
      canonical_url: "https://github.com/example/#{slug}",
      normalized_canonical_url: "https://github.com/example/#{slug}",
      source_provider: :github,
      external_uid: "example/#{slug}"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: title,
      ai_summary: summary,
      source_fingerprint: "#{slug}-v1",
      summary_status: :succeeded,
      review_status: :approved
    )
    resource.publish!(revision: revision)
    resource
  end
end
