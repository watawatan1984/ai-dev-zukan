require "test_helper"

class Search::FacetCountsTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "content type counts add the candidate content type while keeping category and tag filters" do
    mcp_ruby = publish_resource(slug: "facet-content-mcp-ruby", kind: :mcp, source_provider: :github, tags: [ "ruby" ])
    skill_ruby = publish_resource(slug: "facet-content-skill-ruby", kind: :skill, source_provider: :github, tags: [ "ruby" ])
    publish_resource(slug: "facet-content-zenn-python", kind: :zenn_article, source_provider: :zenn, tags: [ "python" ])

    selection = Search::Selection.build(params: {
      content_types: [ "mcp" ],
      category_slugs: [ "coding-development" ],
      tag_slugs: [ "ruby" ]
    })

    counts = Search::FacetCounts.call(selection: selection)

    assert_equal 1, counts.fetch(:content_types).fetch("mcp")
    assert_equal 2, counts.fetch(:content_types).fetch("skill")
    assert_equal 1, counts.fetch(:content_types).fetch("blog")
    expanded = Search::Selection.build(params: selection.to_h.merge(content_types: %w[mcp skill]))
    assert_equal [ mcp_ruby.id ], Search::ResourcesQuery.call(selection: selection).pluck(:id)
    assert_includes Search::ResourcesQuery.call(selection: expanded).pluck(:id), skill_ruby.id
  end

  test "source counts keep non-blog content while restricting only the blog branch" do
    publish_resource(slug: "facet-source-mcp-ruby", kind: :mcp, source_provider: :github, tags: [ "ruby" ])
    publish_resource(slug: "facet-source-zenn-ruby", kind: :zenn_article, source_provider: :zenn, tags: [ "ruby" ])
    publish_resource(slug: "facet-source-qiita-ruby", kind: :qiita_article, source_provider: :qiita, tags: [ "ruby" ])
    publish_resource(slug: "facet-source-qiita-python", kind: :qiita_article, source_provider: :qiita, tags: [ "python" ])

    selection = Search::Selection.build(params: {
      content_types: [ "mcp", "blog" ],
      sources: [ "zenn" ],
      tag_slugs: [ "ruby" ]
    })

    counts = Search::FacetCounts.call(selection: selection)

    assert_equal 2, counts.fetch(:content_types).fetch("blog")
    assert_equal 2, counts.fetch(:sources).fetch("zenn")
    assert_equal 3, counts.fetch(:sources).fetch("qiita")
  end

  test "category counts add the candidate category while preserving content type and tag filters" do
    publish_resource(slug: "facet-category-coding", kind: :mcp, categories: [ "coding-development" ], tags: [ "ruby" ])
    publish_resource(slug: "facet-category-research", kind: :mcp, categories: [ "research-search" ], tags: [ "ruby" ])
    publish_resource(slug: "facet-category-skill", kind: :skill, categories: [ "research-search" ], tags: [ "ruby" ])
    publish_resource(slug: "facet-category-python", kind: :mcp, categories: [ "research-search" ], tags: [ "python" ])

    selection = Search::Selection.build(params: {
      content_types: [ "mcp" ],
      category_slugs: [ "coding-development" ],
      tag_slugs: [ "ruby" ]
    })

    counts = Search::FacetCounts.call(selection: selection)

    assert_equal 1, counts.fetch(:categories).fetch("coding-development")
    assert_equal 2, counts.fetch(:categories).fetch("research-search")
  end

  test "tag counts add the candidate tag while preserving content type and category filters" do
    publish_resource(slug: "facet-tag-ruby", kind: :mcp, categories: [ "coding-development" ], tags: [ "ruby" ])
    publish_resource(slug: "facet-tag-python", kind: :mcp, categories: [ "coding-development" ], tags: [ "python" ])
    publish_resource(slug: "facet-tag-skill-python", kind: :skill, categories: [ "coding-development" ], tags: [ "python" ])
    publish_resource(slug: "facet-tag-research-python", kind: :mcp, categories: [ "research-search" ], tags: [ "python" ])

    selection = Search::Selection.build(params: {
      content_types: [ "mcp" ],
      category_slugs: [ "coding-development" ],
      tag_slugs: [ "ruby" ]
    })

    counts = Search::FacetCounts.call(selection: selection)

    assert_equal 1, counts.fetch(:tags).fetch("ruby")
    assert_equal 2, counts.fetch(:tags).fetch("python")
  end

  test "tag facet includes active tags used at least three times or forced filterable tags" do
    3.times do |index|
      publish_resource(slug: "facet-visible-python-#{index}", tags: [ "python" ])
    end
    publish_resource(slug: "facet-hidden-docker", tags: [ "docker" ])

    counts = Search::FacetCounts.call(selection: Search::Selection.build(params: {}))

    assert_includes counts.fetch(:tags), "ruby"
    assert_includes counts.fetch(:tags), "python"
    refute_includes counts.fetch(:tags), "docker"
  end

  test "tag usage visibility counts only public catalog resources" do
    3.times do |index|
      create_resource(slug: "facet-unpublished-python-#{index}", tags: [ "python" ])
    end
    archived = publish_resource(slug: "facet-archived-python", tags: [ "python" ])
    archived.update!(publication_status: :archived)

    counts = Search::FacetCounts.call(selection: Search::Selection.build(params: {}))

    assert_includes counts.fetch(:tags), "ruby"
    refute_includes counts.fetch(:tags), "python"
  end

  test "inactive category slugs from the taxonomy definition are ignored during selection normalization" do
    definition = Taxonomy::Registry.definition.deep_dup
    definition.fetch("categories").find { |category| category.fetch("slug") == "research-search" }["active"] = false
    original_definition = Taxonomy::Registry.method(:definition)

    Taxonomy::Registry.define_singleton_method(:definition) { definition }
    begin
      selection = Search::Selection.build(params: { category_slugs: [ "research-search" ] })

      assert_empty selection.category_slugs
    ensure
      Taxonomy::Registry.define_singleton_method(:definition) { original_definition.call }
    end
  end

  private

  def publish_resource(slug:, kind: :qiita_article, source_provider: :qiita, categories: [ "coding-development" ], tags: [ "ruby" ])
    resource = Resource.create!(
      kind: kind,
      slug: slug,
      canonical_url: "https://example.com/#{slug}",
      normalized_canonical_url: "https://example.com/#{slug}",
      source_provider: source_provider,
      external_uid: slug,
      published_at: Time.current
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

  def create_resource(slug:, kind: :qiita_article, source_provider: :qiita, categories: [ "coding-development" ], tags: [ "ruby" ])
    resource = Resource.create!(
      kind: kind,
      slug: slug,
      canonical_url: "https://example.com/#{slug}",
      normalized_canonical_url: "https://example.com/#{slug}",
      source_provider: source_provider,
      external_uid: slug
    )
    categories.each do |category_slug|
      resource.resource_categories.create!(category: Category.find_by!(slug: category_slug), origin: :ai)
    end
    tags.each do |tag_slug|
      resource.controlled_resource_tags.create!(tag: Tag.find_by!(slug: tag_slug), origin: :ai)
    end
    resource
  end
end
