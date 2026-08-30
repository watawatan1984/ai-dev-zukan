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
    assert_select ".resource-card h2", text: matching.current_revision.title
    assert_select ".resource-card h2", text: "Alpha Skill", count: 0
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
    assert_select ".resource-card h2", text: mcp.current_revision.title
    assert_select ".resource-card h2", text: skill.current_revision.title
    assert_select ".resource-card h2", text: "Multi Blog", count: 0
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

  test "repeated facet params render selected state active filters and taxonomy explanations" do
    matching = publish_resource(
      slug: "faceted-zenn-ruby",
      title: "Faceted Zenn Ruby",
      summary: "RubyでMCPを扱う記事です。",
      kind: :zenn_article,
      source_provider: :zenn,
      categories: [ "automation-integration", "coding-development" ],
      tags: [ "ruby", "ruby-on-rails" ]
    )
    publish_resource(
      slug: "faceted-qiita-python",
      title: "Faceted Qiita Python",
      summary: "Python記事です。",
      kind: :qiita_article,
      source_provider: :qiita,
      categories: [ "research-search" ],
      tags: [ "python", "mcp" ]
    )

    get resources_path, params: {
      q: "Ruby",
      content_types: %w[blog],
      sources: %w[zenn],
      category_slugs: %w[automation-integration coding-development],
      tag_slugs: %w[ruby ruby-on-rails],
      period: "30d",
      sort: "popular"
    }

    assert_response :success
    assert_select "input[name='q'][value='Ruby']"
    assert_select "input[name='content_types[]'][value='blog'][checked='checked']"
    assert_select "input[name='sources[]'][value='zenn'][checked='checked']"
    assert_select "input[name='category_slugs[]'][value='automation-integration'][checked='checked']"
    assert_select "input[name='category_slugs[]'][value='coding-development'][checked='checked']"
    assert_select "input[name='tag_slugs[]'][value='ruby'][checked='checked']"
    assert_select "input[name='tag_slugs[]'][value='ruby-on-rails'][checked='checked']"
    assert_select "select[name='period'] option[value='30d'][selected='selected']"
    assert_select "select[name='sort'] option[value='popular'][selected='selected']"
    assert_select "[data-active-filters] a", text: "Blog"
    assert_select "[data-active-filters] a", text: "Zenn"
    assert_select "[data-active-filters] a", text: "自動化・外部サービス連携"
    assert_select "[data-active-filters] a[href*='category_slugs%5B%5D=coding-development']"
    assert_select "[data-active-filters] a", text: "すべて解除"
    assert_select ".resource-card h2", text: matching.current_revision.title
    assert_select ".resource-card h2", text: "Faceted Qiita Python", count: 0
    assert_select "[aria-label='一致カテゴリ'] .taxonomy-badge", text: "自動化・外部サービス連携"
    assert_select "[aria-label='一致タグ'] .taxonomy-badge", text: "Ruby"
  end

  test "source controls are hidden unless blog content type is selected" do
    get resources_path

    assert_response :success
    assert_select "[data-source-filter][hidden]"

    get resources_path, params: { content_types: [ "blog" ] }

    assert_response :success
    assert_select "[data-source-filter]:not([hidden])"
  end

  private

  def publish_resource(slug:, title:, summary:, kind: :mcp, source_provider: :github, categories: [], tags: [])
    resource = Resource.create!(
      kind: kind,
      slug: slug,
      canonical_url: "https://github.com/example/#{slug}",
      normalized_canonical_url: "https://github.com/example/#{slug}",
      source_provider: source_provider,
      external_uid: "example/#{slug}",
      source_published_at: Time.current
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: title,
      ai_summary: summary,
      source_fingerprint: "#{slug}-v1",
      summary_status: :succeeded,
      review_status: :approved,
      suggested_category_slugs: categories,
      suggested_tag_slugs: tags
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
