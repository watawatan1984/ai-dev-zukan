require "test_helper"

class SeoDiscoveryTest < ActionDispatch::IntegrationTest
  test "sitemap includes only published resource URLs" do
    published = publish_resource("published-mcp")
    Resource.create!(
      kind: :skill,
      slug: "private-skill",
      canonical_url: "https://example.com/private-skill",
      normalized_canonical_url: "https://example.com/private-skill",
      source_provider: :manual
    )

    get sitemap_path(format: :xml)

    assert_response :success
    assert_includes response.body, resource_url(published.slug)
    refute_includes response.body, "private-skill"
  end

  test "resource detail exposes canonical and JSON-LD metadata" do
    resource = publish_resource("structured-mcp")

    get resource_path(resource.slug)

    assert_response :success
    assert_select "link[rel='canonical'][href='#{resource_url(resource.slug)}']"
    assert_select "script[type='application/ld+json']"
  end

  private

  def publish_resource(slug)
    resource = Resource.create!(
      kind: :mcp,
      slug: slug,
      canonical_url: "https://example.com/#{slug}",
      normalized_canonical_url: "https://example.com/#{slug}",
      source_provider: :manual
    )
    revision = resource.revisions.create!(
      origin: :manual,
      title: slug.humanize,
      ai_summary: "構造化データ用の要約です。",
      source_fingerprint: "#{slug}-v1",
      summary_status: :manually_written,
      review_status: :approved
    )
    resource.publish!(revision:)
    resource
  end
end
