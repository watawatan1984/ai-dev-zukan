require "test_helper"

class Search::ResourcesQueryTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "query returns matching published resources and excludes unpublished candidates" do
    published = create_resource_with_revision(
      slug: "solid-queue-guide",
      title: "Solid Queue実践ガイド",
      summary: "Railsでバックグラウンドジョブを運用する方法を解説します。",
      review_status: :approved
    )
    published.publish!(revision: published.revisions.first)

    create_resource_with_revision(
      slug: "private-solid-queue-guide",
      title: "未公開のSolid Queue記事",
      summary: "この候補は検索結果に表示されません。",
      review_status: :review_pending
    )

    results = Search::ResourcesQuery.call(selection: Search::Selection.build(params: { q: "Solid Queue" }))

    assert_equal [ published ], results.to_a
  end

  test "signed in user does not receive hidden resources" do
    user = users(:regular)
    resource = create_resource_with_revision(
      slug: "hidden-mcp",
      title: "Hidden MCP",
      summary: "非表示にするMCPです。",
      review_status: :approved
    )
    resource.publish!(revision: resource.revisions.first)
    user.hidden_resources.create!(resource: resource)

    results = Search::ResourcesQuery.call(selection: Search::Selection.build(params: {}), user: user)

    assert_empty results
  end

  test "period filter uses the original publication date" do
    recent = create_resource_with_revision(
      slug: "recent-article",
      title: "Recent article",
      summary: "最近の記事です。",
      review_status: :approved,
      source_published_at: 2.days.ago
    )
    old = create_resource_with_revision(
      slug: "old-article",
      title: "Old article",
      summary: "古い記事です。",
      review_status: :approved,
      source_published_at: 2.years.ago
    )
    [ recent, old ].each { |resource| resource.publish!(revision: resource.revisions.first) }

    results = Search::ResourcesQuery.call(selection: Search::Selection.build(params: { period: "30d" }))

    assert_equal [ recent ], results.to_a
  end

  test "content types are OR within the facet" do
    mcp = publish_search_resource(slug: "or-mcp", kind: :mcp, source_provider: :github)
    skill = publish_search_resource(slug: "or-skill", kind: :skill, source_provider: :github)
    publish_search_resource(slug: "or-zenn", kind: :zenn_article, source_provider: :zenn)

    results = query(content_types: %w[mcp skill])

    assert_equal [ mcp, skill ].map(&:id).sort, results.pluck(:id).sort
  end

  test "categories are OR within the facet" do
    coding = publish_search_resource(slug: "category-coding", categories: [ "coding-development" ])
    research = publish_search_resource(slug: "category-research", categories: [ "research-search" ])
    publish_search_resource(slug: "category-security", categories: [ "security-governance" ])

    results = query(category_slugs: %w[research-search coding-development])

    assert_equal [ coding, research ].map(&:id).sort, results.pluck(:id).sort
  end

  test "tags are OR within the facet" do
    ruby = publish_search_resource(slug: "tag-ruby", tags: [ "ruby" ])
    python = publish_search_resource(slug: "tag-python", tags: [ "python" ])
    publish_search_resource(slug: "tag-docker", tags: [ "docker" ])

    results = query(tag_slugs: %w[python ruby])

    assert_equal [ ruby, python ].map(&:id).sort, results.pluck(:id).sort
  end

  test "different facets are ANDed after each facet applies OR" do
    mcp_ruby = publish_search_resource(
      slug: "and-mcp-ruby",
      kind: :mcp,
      categories: [ "coding-development" ],
      tags: [ "ruby" ]
    )
    skill_python = publish_search_resource(
      slug: "and-skill-python",
      kind: :skill,
      categories: [ "research-search" ],
      tags: [ "python" ]
    )
    publish_search_resource(
      slug: "and-zenn-ruby",
      kind: :zenn_article,
      source_provider: :zenn,
      categories: [ "coding-development" ],
      tags: [ "ruby" ]
    )
    publish_search_resource(
      slug: "and-mcp-security",
      kind: :mcp,
      categories: [ "security-governance" ],
      tags: [ "ruby" ]
    )

    results = query(
      content_types: %w[mcp skill],
      category_slugs: %w[coding-development research-search],
      tag_slugs: %w[ruby python]
    )

    assert_equal [ mcp_ruby, skill_python ].map(&:id).sort, results.pluck(:id).sort
  end

  test "mcp or blog and zenn keeps mcp while restricting the blog branch" do
    mcp = publish_search_resource(slug: "branch-mcp", kind: :mcp, source_provider: :github)
    zenn = publish_search_resource(slug: "branch-zenn", kind: :zenn_article, source_provider: :zenn)
    publish_search_resource(slug: "branch-qiita", kind: :qiita_article, source_provider: :qiita)
    publish_search_resource(slug: "branch-skill", kind: :skill, source_provider: :github)

    results = query(content_types: %w[mcp blog], sources: %w[zenn])

    assert_equal [ mcp, zenn ].map(&:id).sort, results.pluck(:id).sort
  end

  test "blog without source includes zenn and qiita" do
    zenn = publish_search_resource(slug: "blog-zenn", kind: :zenn_article, source_provider: :zenn)
    qiita = publish_search_resource(slug: "blog-qiita", kind: :qiita_article, source_provider: :qiita)
    publish_search_resource(slug: "blog-mcp", kind: :mcp, source_provider: :github)

    results = query(content_types: %w[blog])

    assert_equal [ zenn, qiita ].map(&:id).sort, results.pluck(:id).sort
  end

  test "source without blog is ignored by normalization" do
    mcp = publish_search_resource(slug: "source-mcp", kind: :mcp, source_provider: :github)
    skill = publish_search_resource(slug: "source-skill", kind: :skill, source_provider: :github)
    publish_search_resource(slug: "source-zenn", kind: :zenn_article, source_provider: :zenn)

    results = query(content_types: %w[mcp skill], sources: %w[zenn])

    assert_equal [ mcp, skill ].map(&:id).sort, results.pluck(:id).sort
  end

  test "multiple category and tag joins return each resource once" do
    resource = publish_search_resource(
      slug: "distinct-resource",
      categories: %w[coding-development research-search],
      tags: %w[ruby python]
    )

    results = query(
      category_slugs: %w[coding-development research-search],
      tag_slugs: %w[ruby python]
    )

    assert_equal [ resource.id ], results.pluck(:id)
  end

  test "sort newest still works with normalized facets" do
    old = publish_search_resource(slug: "old-sorted", published_at: 2.days.ago)
    newest = publish_search_resource(slug: "newest-sorted", published_at: 1.hour.ago)

    results = query(content_types: %w[blog], sort: "newest")

    assert_equal [ newest, old ], results.to_a
  end

  private

  def query(params)
    Search::ResourcesQuery.call(selection: Search::Selection.build(params: params))
  end

  def publish_search_resource(slug:, kind: :qiita_article, source_provider: :qiita, categories: [ "coding-development" ], tags: [ "ruby" ], published_at: Time.current)
    resource = Resource.create!(
      kind: kind,
      slug: slug,
      canonical_url: "https://example.com/#{slug}",
      normalized_canonical_url: "https://example.com/#{slug}",
      source_provider: source_provider,
      external_uid: slug,
      source_published_at: published_at,
      published_at: published_at
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: slug.titleize,
      ai_summary: "#{slug} summary",
      source_fingerprint: "#{slug}-fingerprint",
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

  def create_resource_with_revision(slug:, title:, summary:, review_status:, source_published_at: nil)
    resource = Resource.create!(
      kind: :qiita_article,
      slug: slug,
      canonical_url: "https://qiita.com/example/items/#{slug}",
      normalized_canonical_url: "https://qiita.com/example/items/#{slug}",
      source_provider: :qiita,
      external_uid: slug,
      source_published_at: source_published_at
    )
    resource.revisions.create!(
      origin: :imported,
      title: title,
      ai_summary: summary,
      source_fingerprint: "#{slug}-fingerprint",
      summary_status: :succeeded,
      review_status: review_status
    )
    resource
  end
end
