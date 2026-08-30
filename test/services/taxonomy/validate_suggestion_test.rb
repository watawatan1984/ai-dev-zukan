require "test_helper"

class Taxonomy::ValidateSuggestionTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "accepts one to three categories and two to six canonical tags" do
    revision = build_revision(
      suggested_category_slugs: [ "automation-integration", "research-search" ],
      suggested_tag_slugs: [ "ruby", "api-integration" ]
    )

    assert Taxonomy::ValidateSuggestion.call(revision:).valid?
  end

  test "rejects unknown, duplicate, underfilled, and overfilled values" do
    revision = build_revision(
      suggested_category_slugs: [ "unknown" ],
      suggested_tag_slugs: [ "ruby", "ruby" ]
    )

    result = Taxonomy::ValidateSuggestion.call(revision:)

    assert_not result.valid?
    assert_includes result.errors, "unknown category: unknown"
    assert_includes result.errors, "duplicate tag: ruby"
  end

  test "resolves tag aliases before validation" do
    revision = build_revision(
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "rails", "test-driven-development" ]
    )

    result = Taxonomy::ValidateSuggestion.call(revision:)

    assert_predicate result, :valid?
    assert_equal [ "ruby-on-rails", "tdd" ], result.tag_slugs
  end

  test "does not parameterize unknown tag display text into a valid slug" do
    revision = build_revision(
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "Ruby on Rails", "testing" ]
    )

    result = Taxonomy::ValidateSuggestion.call(revision:)

    assert_not result.valid?
    assert_includes result.errors, "unknown tag: ruby on rails"
  end

  test "rejects active categories outside the fixed taxonomy definition" do
    Category.create!(
      slug: "admin-added-category",
      name: "Admin Added Category",
      active: true
    )
    revision = build_revision(
      suggested_category_slugs: [ "admin-added-category" ],
      suggested_tag_slugs: [ "ruby", "testing" ]
    )

    result = Taxonomy::ValidateSuggestion.call(revision:)

    assert_not result.valid?
    assert_includes result.errors, "unknown category: admin-added-category"
  end

  test "allows active db-only tags but rejects inactive tags" do
    Tag.create!(
      slug: "admin-audited-tool",
      name: "Admin Audited Tool",
      normalized_name: "admin-audited-tool",
      active: true
    )
    Tag.create!(
      slug: "inactive-admin-tool",
      name: "Inactive Admin Tool",
      normalized_name: "inactive-admin-tool",
      active: false
    )

    accepted = build_revision(
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "admin-audited-tool", "testing" ]
    )
    rejected = build_revision(
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "inactive-admin-tool", "testing" ]
    )

    assert_predicate Taxonomy::ValidateSuggestion.call(revision: accepted), :valid?
    result = Taxonomy::ValidateSuggestion.call(revision: rejected)
    assert_not result.valid?
    assert_includes result.errors, "unknown tag: inactive-admin-tool"
  end

  test "rejects content type tags that only restate mcp or skill resources" do
    mcp_revision = build_revision(
      kind: :mcp,
      suggested_category_slugs: [ "automation-integration" ],
      suggested_tag_slugs: [ "mcp", "github" ]
    )
    skill_revision = build_revision(
      kind: :skill,
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "agent-skills", "ruby" ]
    )

    assert_includes Taxonomy::ValidateSuggestion.call(revision: mcp_revision).errors, "tag restates content type: mcp"
    assert_includes Taxonomy::ValidateSuggestion.call(revision: skill_revision).errors, "tag restates content type: agent-skills"
  end

  test "allows mcp and agent skills tags on blog resources" do
    revision = build_revision(
      kind: :zenn_article,
      suggested_category_slugs: [ "documentation-knowledge" ],
      suggested_tag_slugs: [ "mcp", "agent-skills" ]
    )

    assert_predicate Taxonomy::ValidateSuggestion.call(revision:), :valid?
  end

  test "normalizes and bounds search keywords" do
    revision = build_revision(
      suggested_category_slugs: [ "research-search" ],
      suggested_tag_slugs: [ "ruby", "api-integration" ],
      search_keywords: [ "  GitHub  MCP  ", "x" * 81 ]
    )

    result = Taxonomy::ValidateSuggestion.call(revision:)

    assert_not result.valid?
    assert_includes result.search_keywords, "github mcp"
    assert_includes result.errors, "search keyword too long: #{'x' * 81}"
  end

  private

  def build_revision(kind: :zenn_article, suggested_category_slugs:, suggested_tag_slugs:, search_keywords: [])
    resource = Resource.create!(
      kind:,
      source_provider: kind == :qiita_article ? :qiita : :manual,
      slug: "taxonomy-validation-#{SecureRandom.hex(6)}",
      canonical_url: "https://example.com/#{SecureRandom.hex(6)}",
      normalized_canonical_url: "https://example.com/#{SecureRandom.hex(6)}"
    )

    resource.revisions.create!(
      origin: :imported,
      title: "Taxonomy validation",
      source_fingerprint: SecureRandom.hex(12),
      ai_summary: "A resource for taxonomy validation.",
      suggested_category_slugs:,
      suggested_tag_slugs:,
      search_keywords:,
      summary_status: :succeeded,
      review_status: :review_pending
    )
  end
end
