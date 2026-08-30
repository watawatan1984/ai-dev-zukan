require "test_helper"

class Search::SelectionTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "normalizes repeated values by controlled registry order" do
    selection = Search::Selection.build(
      params: {
        q: "  Rails  ",
        content_types: [ "blog", "mcp", "mcp", "unknown" ],
        sources: [ "qiita", "zenn", "github" ],
        category_slugs: [ "learning-career", "coding-development", "unknown" ],
        tag_slugs: [ "rails", "ruby", "missing" ],
        period: "30d",
        sort: "popular"
      }
    )

    assert_equal "Rails", selection.query
    assert_equal %w[mcp blog], selection.content_types
    assert_equal %w[zenn qiita], selection.sources
    assert_equal %w[coding-development learning-career], selection.category_slugs
    assert_equal %w[ruby ruby-on-rails], selection.tag_slugs
    assert_equal "30d", selection.period
    assert_equal "popular", selection.sort
  end

  test "removes source values when blog is not selected" do
    selection = Search::Selection.build(
      params: {
        content_types: [ "mcp", "skill" ],
        sources: [ "zenn", "qiita" ]
      }
    )

    assert_equal %w[mcp skill], selection.content_types
    assert_empty selection.sources
  end

  test "serializes normalized state and removes one selected facet value" do
    selection = Search::Selection.build(
      params: {
        q: "ruby",
        content_types: [ "blog", "mcp" ],
        sources: [ "zenn" ],
        tag_slugs: [ "rails", "ruby" ],
        period: "7d",
        sort: "newest"
      }
    )

    assert_equal(
      {
        q: "ruby",
        content_types: %w[mcp blog],
        sources: %w[zenn],
        tag_slugs: %w[ruby ruby-on-rails],
        period: "7d",
        sort: "newest"
      },
      selection.to_h
    )
    assert_includes selection.to_query, "content_types%5B%5D=mcp"

    without_blog = selection.without(:content_types, "blog")

    assert_equal %w[mcp], without_blog.content_types
    assert_empty without_blog.sources
    assert_predicate selection, :filtered?
  end

  test "raises instead of truncating over cap values" do
    assert_raises(Search::Selection::TooManyValues) do
      Search::Selection.build(params: { tag_slugs: Taxonomy::Registry.tag_slugs.first(21) })
    end
  end

  test "removes scalar filters when chip value matches current selection" do
    selection = Search::Selection.build(
      params: {
        q: "ruby",
        period: "30d",
        sort: "popular",
        content_types: [ "mcp" ]
      }
    )

    assert_nil selection.without(:q, "ruby").query
    assert_nil selection.without(:query, "ruby").query
    assert_nil selection.without(:period, "30d").period
    assert_equal "relevance", selection.without(:sort, "popular").sort
    assert_equal %w[mcp], selection.without(:sort, "popular").content_types
  end

  test "keeps scalar filters when chip value does not match current selection" do
    selection = Search::Selection.build(
      params: {
        q: "ruby",
        period: "30d",
        sort: "popular"
      }
    )

    assert_equal "ruby", selection.without(:q, "rails").query
    assert_equal "30d", selection.without(:period, "7d").period
    assert_equal "popular", selection.without(:sort, "newest").sort
  end
end
