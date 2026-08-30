require "test_helper"

class PublicDiscoveryTest < ActionDispatch::IntegrationTest
  setup do
    Taxonomy::SyncVocabulary.call
  end

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
    assert_select "select[name='period']"
  end

  test "over cap facet arrays return bad request" do
    get resources_path, params: { tag_slugs: Taxonomy::Registry.tag_slugs.first(21) }

    assert_response :bad_request
  end

  test "multi select content params filter the public catalog" do
    mcp = publish_resource(slug: "multi-mcp", title: "Multi MCP", summary: "MCPです。", kind: :mcp, source_provider: :github)
    skill = publish_resource(slug: "multi-skill", title: "Multi Skill", summary: "Skillです。", kind: :skill, source_provider: :github)
    publish_resource(slug: "multi-blog", title: "Multi Blog", summary: "記事です。", kind: :qiita_article, source_provider: :qiita)

    get resources_path, params: { content_types: %w[mcp skill] }

    assert_response :success
    assert_select "h2", text: mcp.current_revision.title
    assert_select "h2", text: skill.current_revision.title
    assert_select "h2", text: "Multi Blog", count: 0
  end

  test "index search uses a bounded number of SQL queries with facet counts" do
    publish_resource(
      slug: "query-count-mcp",
      title: "Query Count MCP",
      summary: "MCPです。",
      kind: :mcp,
      source_provider: :github,
      categories: [ "coding-development" ],
      tags: [ "ruby" ]
    )
    publish_resource(
      slug: "query-count-zenn",
      title: "Query Count Zenn",
      summary: "Zenn記事です。",
      kind: :zenn_article,
      source_provider: :zenn,
      categories: [ "coding-development" ],
      tags: [ "ruby" ]
    )

    sql_count = count_index_sql do
      get resources_path, params: {
        content_types: %w[mcp blog],
        sources: %w[zenn],
        category_slugs: %w[coding-development],
        tag_slugs: %w[ruby]
      }
    end

    assert_response :success
    assert_operator sql_count, :<=, 12
  end

  private

  def publish_resource(slug:, title:, summary:, kind: :mcp, source_provider: :github, categories: [], tags: [])
    resource = Resource.create!(
      kind: kind,
      slug: slug,
      canonical_url: "https://github.com/example/#{slug}",
      normalized_canonical_url: "https://github.com/example/#{slug}",
      source_provider: source_provider,
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
    categories.each do |category_slug|
      resource.resource_categories.create!(category: Category.find_by!(slug: category_slug), origin: :ai)
    end
    tags.each do |tag_slug|
      resource.controlled_resource_tags.create!(tag: Tag.find_by!(slug: tag_slug), origin: :ai)
    end
    resource
  end

  def count_index_sql
    count = 0
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      count += 1
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      yield
    end

    count
  end
end
