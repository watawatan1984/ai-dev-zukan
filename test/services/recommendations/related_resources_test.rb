require "test_helper"

class Recommendations::RelatedResourcesTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "scores shared controlled categories and tags with separate reason payloads" do
    current = publish_resource(
      slug: "current-controlled-mcp",
      title: "Current Controlled MCP",
      kind: :mcp,
      categories: %w[coding-development automation-integration],
      tags: %w[ruby ruby-on-rails]
    )
    strongest = publish_resource(
      slug: "strongest-controlled-skill",
      title: "Strongest Controlled Skill",
      kind: :skill,
      categories: %w[coding-development automation-integration],
      tags: %w[ruby ruby-on-rails],
      popularity_score: 0.01
    )
    partial = publish_resource(
      slug: "partial-controlled-mcp",
      title: "Partial Controlled MCP",
      kind: :mcp,
      categories: %w[coding-development],
      tags: %w[ruby],
      popularity_score: 0.99
    )

    recommendations = Recommendations::RelatedResources.call(resource: current, limit: 2)

    assert_equal strongest, recommendations.first.resource
    assert_equal partial, recommendations.second.resource
    assert_equal [ "コード作成・開発支援", "自動化・外部サービス連携" ], recommendations.first.reasons.fetch(:categories)
    assert_equal [ "Ruby", "Ruby on Rails" ], recommendations.first.reasons.fetch(:tags)
    assert_operator recommendations.first.score, :>, recommendations.second.score
  end

  test "legacy category and tags alone do not create taxonomy recommendation reasons" do
    legacy_category = Category.create!(name: "Legacy Category", slug: "legacy-category")
    legacy_tag = Tag.create!(name: "Legacy Tag", normalized_name: "legacy-tag", slug: "legacy-tag")
    current = publish_resource(
      slug: "current-legacy-only",
      title: "Current Legacy Only",
      kind: :mcp,
      legacy_category: legacy_category,
      legacy_tags: [ legacy_tag ]
    )
    legacy_match = publish_resource(
      slug: "candidate-legacy-only",
      title: "Candidate Legacy Only",
      kind: :qiita_article,
      legacy_category: legacy_category,
      legacy_tags: [ legacy_tag ]
    )

    recommendations = Recommendations::RelatedResources.call(resource: current, limit: 4)

    refute_includes recommendations.map(&:resource), legacy_match
  end

  test "ranks shared tags and kind with an explainable reason" do
    current = publish_resource(slug: "current-mcp", title: "Current MCP", kind: :mcp, tags: [ "mcp" ])
    related = publish_resource(slug: "related-mcp", title: "Related MCP", kind: :mcp, tags: [ "mcp" ])
    unrelated = publish_resource(slug: "unrelated-article", title: "Unrelated Article", kind: :qiita_article)
    unrelated.update!(popularity_score: 0.99)

    recommendations = Recommendations::RelatedResources.call(resource: current, limit: 2)

    assert_equal related, recommendations.first.resource
    assert_includes recommendations.first.reasons.fetch(:tags), "MCP"
    assert_includes recommendations.first.reasons.fetch(:kinds), "同じMCP"
  end

  private

  def publish_resource(slug:, title:, kind:, categories: [], tags: [], legacy_category: nil, legacy_tags: [], popularity_score: 0.0)
    resource = Resource.create!(
      kind: kind,
      slug: slug,
      canonical_url: "https://example.com/#{slug}",
      normalized_canonical_url: "https://example.com/#{slug}",
      source_provider: :manual,
      category: legacy_category,
      popularity_score: popularity_score,
      published_at: Time.current
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
    categories.each do |category_slug|
      resource.resource_categories.create!(category: Category.find_by!(slug: category_slug), origin: :ai)
    end
    tags.each do |tag_slug|
      resource.controlled_resource_tags.create!(tag: Tag.find_by!(slug: tag_slug), origin: :ai)
    end
    legacy_tags.each { |tag| resource.tags << tag }
    resource
  end
end
