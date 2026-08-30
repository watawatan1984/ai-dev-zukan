require "test_helper"

class SeoDiscoveryTest < ActionDispatch::IntegrationTest
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "unfiltered resource listing is indexable with a bare canonical" do
    publish_resource("indexable-mcp")

    get resources_path

    assert_response :success
    assert_select "meta[name='robots']", count: 0
    assert_select "link[rel='canonical'][href='#{resources_url}']"
  end

  test "filtered resource listing is noindex follow with a bare canonical" do
    publish_resource("filtered-mcp")

    get resources_path, params: { content_types: [ "mcp" ], category_slugs: [ "coding-development" ], tag_slugs: [ "ruby" ] }

    assert_response :success
    assert_select "meta[name='robots'][content='noindex, follow']"
    assert_select "link[rel='canonical'][href='#{resources_url}']"
  end

  test "search resource listing is noindex follow" do
    publish_resource("searched-mcp")

    get resources_path, params: { q: "searched" }

    assert_response :success
    assert_select "meta[name='robots'][content='noindex, follow']"
    assert_select "link[rel='canonical'][href='#{resources_url}']"
  end

  test "ignored raw params do not create a noindex listing variant" do
    publish_resource("ignored-param-mcp")

    get resources_path, params: { sources: [ "zenn" ], content_types: [ "unknown" ], tag_slugs: [ "unknown-tag" ], junk: "1" }

    assert_response :success
    assert_select "meta[name='robots']", count: 0
    assert_select "link[rel='canonical'][href='#{resources_url}']"
  end

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

  test "resource detail renders related reason payload accessibly and escaped" do
    unsafe_tag = Tag.create!(
      name: "<script>alert(1)</script>",
      normalized_name: "unsafe-tag",
      slug: "unsafe-tag",
      vocabulary_group: "technique_architecture",
      active: true,
      filterable: false
    )
    resource = publish_resource("reason-current")
    related = publish_resource("reason-related")
    [ resource, related ].each do |item|
      item.controlled_resource_tags.create!(tag: unsafe_tag, origin: :admin)
    end

    get resource_path(resource.slug)

    assert_response :success
    assert_select "[aria-label='関連理由'] .taxonomy-badge", text: "カテゴリ: コード作成・開発支援"
    assert_select "[aria-label='関連理由'] .taxonomy-badge", text: "タグ: <script>alert(1)</script>"
    refute_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
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
      review_status: :approved,
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "ruby", "mcp" ]
    )
    resource.publish!(revision:)
    resource.resource_categories.create!(category: Category.find_by!(slug: "coding-development"), origin: :ai)
    resource.controlled_resource_tags.create!(tag: Tag.find_by!(slug: "ruby"), origin: :ai)
    resource.controlled_resource_tags.create!(tag: Tag.find_by!(slug: "mcp"), origin: :ai)
    resource
  end
end
