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
    assert_select ".filter-panel[role]", count: 0
    assert_select ".filter-panel[aria-modal]", count: 0
    assert_select "[data-source-filter][hidden]"
    assert_select "[data-source-filter] input[name='sources[]'][disabled='disabled']", 2
    assert_select "[data-facet-filter-target='selectionCount']", text: "0件選択中"

    get resources_path, params: { content_types: [ "blog" ] }

    assert_response :success
    assert_select "[data-source-filter]:not([hidden])"
    assert_select "[data-source-filter] input[name='sources[]'][disabled='disabled']", count: 0
  end

  test "source params do not render as active selections without blog" do
    get resources_path, params: { sources: [ "zenn" ] }

    assert_response :success
    assert_select "[data-source-filter][hidden]"
    assert_select "input[name='sources[]'][value='zenn'][checked='checked']", count: 0
    assert_select "[data-active-filters]", count: 0
  end

  test "public discovery explains the search model and labels active filters accessibly" do
    get resources_path, params: { q: "Ruby", content_types: [ "mcp" ], tag_slugs: [ "ruby" ] }

    assert_response :success
    assert_select "[data-search-model-help]", text: /同じ欄ではOR、欄をまたぐとANDで絞り込みます。/
    assert_select "[data-facet-count-help]", text: /条件を追加した後の検索結果件数/
    assert_select "[data-resource-definitions]", text: /MCP: AIと外部ツールをつなぐ仕組み/
    assert_select "[data-resource-definitions]", text: /Skill: AIエージェント向けの手順・機能/
    assert_select "[data-resource-definitions]", text: /Blog: Zenn・Qiitaの技術記事/
    assert_select "[data-active-filters] a[aria-label='MCP の絞り込みを解除']"
    assert_select "[data-active-filters] a[aria-label='検索語「Ruby」の絞り込みを解除']"
  end

  test "zero results offer query, facet, and full recovery paths" do
    get resources_path, params: { q: "no-such-resource", content_types: [ "mcp" ] }

    assert_response :success
    assert_select ".empty-state a[href*='content_types']", text: /検索語だけ解除/
    assert_select ".empty-state a[href*='q=no-such-resource']", text: /絞り込みだけ解除/
    assert_select ".empty-state a[href='/resources']", text: "すべての条件を解除"
  end

  test "filtered discovery uses a compact hero and anonymous visitors see registration benefit" do
    get resources_path, params: { q: "Ruby" }

    assert_response :success
    assert_select ".compact-hero"
    assert_select ".registration-benefit", text: /無料登録すると、リソースを保存・非表示にできます。/

    get resources_path

    assert_response :success
    assert_select ".landing-hero"
  end

  test "detail links preserve safe filtered return path and reject unsafe values" do
    resource = publish_resource(slug: "return-path-mcp", title: "Return Path MCP", summary: "MCPです。")

    get resources_path, params: { q: "Return", content_types: [ "mcp" ] }
    assert_response :success
    assert_select ".resource-card a[href*='return_to=']"

    get resource_path(resource.slug), params: { return_to: resources_path(q: "Return", content_types: [ "mcp" ]) }
    assert_response :success
    assert_select "a.back-link[href*='q=Return']"

    [ "https://evil.example/", "//evil.example/resources", "not a path", "/admin" ].each do |unsafe|
      get resource_path(resource.slug), params: { return_to: unsafe }
      assert_response :success
      assert_select "a.back-link[href='/resources']"
    end
  end

  test "detail presentation has an early source CTA, Japanese date, and provider popularity label" do
    resource = publish_resource(slug: "presentation-zenn", title: "Presentation Zenn", summary: "記事です.", kind: :zenn_article, source_provider: :zenn)
    resource.update!(popularity_raw: 1234)
    github = publish_resource(slug: "presentation-github", title: "Presentation GitHub", summary: "MCPです.", kind: :mcp, source_provider: :github)
    github.update!(popularity_raw: 42)
    qiita = publish_resource(slug: "presentation-qiita", title: "Presentation Qiita", summary: "記事です.", kind: :qiita_article, source_provider: :qiita)
    qiita.update!(popularity_raw: 84)

    get resources_path
    assert_response :success
    assert_select ".resource-card time", text: /年.*月.*日/
    assert_select ".resource-card .card-stats", text: /Zenn いいね/
    assert_select ".resource-card .card-stats", text: /GitHub Stars/
    assert_select ".resource-card .card-stats", text: /Qiita いいね/

    get resource_path(resource.slug)
    assert_response :success
    assert_select ".source-cta-top a", text: "Zennで見る ↗"
    assert_select ".resource-detail > .source-cta-top + .summary-card"
    assert_select ".source-card"
    assert_select ".detail-byline time", text: /年.*月.*日/
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
