require "test_helper"

class Taxonomy::GenerateSuggestionTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  FakeTaxonomizer = Struct.new(:result) do
    attr_reader :calls

    def call(revision:)
      @calls = calls.to_i + 1
      raise "revision must be processing before classification" unless revision.taxonomy_status_processing?

      result
    end
  end

  test "claims a queued revision and persists a validated taxonomy suggestion" do
    revision = build_revision(taxonomy_status: :queued)
    result = Ai::TaxonomySuggestion.new(
      category_slugs: [ "automation-integration" ],
      tag_slugs: [ "ruby", "api-integration" ],
      search_keywords: [ "Solid Queue" ],
      confidence: 0.92,
      provider: "nvidia",
      model: "test-model",
      prompt_version: "catalog-taxonomy-v2"
    )
    taxonomizer = FakeTaxonomizer.new(result)

    Taxonomy::GenerateSuggestion.call(revision:, taxonomizer:)

    revision.reload
    assert_equal 1, taxonomizer.calls
    assert_predicate revision, :taxonomy_status_succeeded?
    assert_predicate revision, :taxonomy_origin_ai?
    assert_predicate revision, :review_pending?
    assert_equal [ "automation-integration" ], revision.suggested_category_slugs
    assert_equal [ "ruby", "api-integration" ], revision.suggested_tag_slugs
    assert_equal [ "solid queue" ], revision.search_keywords
    assert_equal BigDecimal("0.92"), revision.taxonomy_confidence
    assert_equal "nvidia", revision.taxonomy_provider
    assert_equal "test-model", revision.taxonomy_model
    assert_equal "catalog-taxonomy-v2", revision.taxonomy_prompt_version
    assert_equal expected_input_sha(revision), revision.taxonomy_input_sha256
    assert revision.taxonomy_generated_at.present?
  end

  test "marks invalid suggestions failed without touching a published resource" do
    published = build_revision(
      title: "Published",
      source_fingerprint: "published-#{SecureRandom.hex(6)}",
      taxonomy_status: :succeeded,
      review_status: :review_pending,
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "ruby", "testing" ]
    )
    resource = published.resource
    Editorial::ApproveAndPublish.call(revision: published, reviewer: users(:admin))
    candidate = resource.revisions.create!(
      origin: :imported,
      title: "Candidate",
      source_excerpt: "Candidate excerpt",
      source_fingerprint: "candidate-#{SecureRandom.hex(6)}",
      ai_summary: "Candidate summary",
      capabilities: [ "Candidate capability" ],
      key_points: [ "Candidate point" ],
      summary_status: :succeeded,
      taxonomy_status: :queued,
      review_status: :draft
    )
    result = Ai::TaxonomySuggestion.new(
      category_slugs: [ "unknown" ],
      tag_slugs: [ "ruby", "api-integration" ],
      search_keywords: [ "Candidate" ],
      confidence: 0.8,
      provider: "nvidia",
      model: "test-model",
      prompt_version: "catalog-taxonomy-v2"
    )

    assert_raises(Taxonomy::GenerateSuggestion::InvalidSuggestion) do
      Taxonomy::GenerateSuggestion.call(revision: candidate, taxonomizer: FakeTaxonomizer.new(result))
    end

    candidate.reload
    assert_predicate candidate, :taxonomy_status_failed?
    assert_equal [], candidate.suggested_category_slugs
    assert_equal [], candidate.suggested_tag_slugs
    assert_equal published, resource.reload.current_revision
    assert_equal [ "coding-development" ], resource.controlled_categories.pluck(:slug)
    assert_equal %w[ruby testing], resource.controlled_tags.order(:slug).pluck(:slug)
  end

  test "is idempotent for succeeded and concurrently claimed revisions" do
    succeeded = build_revision(taxonomy_status: :succeeded)
    processing = build_revision(taxonomy_status: :processing)
    result = Ai::TaxonomySuggestion.new(
      category_slugs: [ "automation-integration" ],
      tag_slugs: [ "ruby", "api-integration" ],
      search_keywords: [],
      confidence: 0.9,
      provider: "nvidia",
      model: "test-model",
      prompt_version: "catalog-taxonomy-v2"
    )
    taxonomizer = FakeTaxonomizer.new(result)

    Taxonomy::GenerateSuggestion.call(revision: succeeded, taxonomizer:)
    Taxonomy::GenerateSuggestion.call(revision: processing, taxonomizer:)

    assert_equal 0, taxonomizer.calls.to_i
    assert_predicate succeeded.reload, :taxonomy_status_succeeded?
    assert_predicate processing.reload, :taxonomy_status_processing?
  end

  test "does not claim or fail an approved revision" do
    approved = build_revision(
      taxonomy_status: :queued,
      review_status: :review_pending,
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "ruby", "testing" ]
    )
    Editorial::ApproveAndPublish.call(revision: approved, reviewer: users(:admin))
    approved.update_columns(
      taxonomy_status: ResourceRevision.taxonomy_statuses.fetch("queued"),
      taxonomy_input_sha256: nil
    )
    taxonomizer = Class.new do
      attr_reader :calls

      def call(revision:)
        @calls = calls.to_i + 1
        raise "approved revisions must not be classified"
      end
    end.new

    Taxonomy::GenerateSuggestion.call(revision: approved, taxonomizer:)

    approved.reload
    assert_equal 0, taxonomizer.calls.to_i
    assert_predicate approved, :approved?
    assert_predicate approved, :taxonomy_status_queued?
    assert_nil approved.taxonomy_input_sha256
  end

  test "does not mark a revision failed if it becomes approved after claim" do
    revision = build_revision(taxonomy_status: :queued)
    taxonomizer = Class.new do
      def call(revision:)
        revision.update_columns(review_status: ResourceRevision.review_statuses.fetch("approved"))
        raise Faraday::TimeoutError, "provider timeout"
      end
    end.new

    assert_raises(Faraday::TimeoutError) do
      Taxonomy::GenerateSuggestion.call(revision:, taxonomizer:)
    end

    revision.reload
    assert_predicate revision, :approved?
    assert_predicate revision, :taxonomy_status_processing?
  end

  private

  def build_revision(
    title: "Solid Queue Guide",
    source_excerpt: "RailsでSolid Queueを使う記事です。",
    source_fingerprint: SecureRandom.hex(12),
    taxonomy_status: :queued,
    review_status: :draft,
    suggested_category_slugs: [],
    suggested_tag_slugs: []
  )
    resource = Resource.create!(
      kind: :zenn_article,
      slug: "taxonomy-generation-#{SecureRandom.hex(6)}",
      canonical_url: "https://example.com/#{SecureRandom.hex(6)}",
      normalized_canonical_url: "https://example.com/#{SecureRandom.hex(6)}",
      source_provider: :zenn
    )

    resource.revisions.create!(
      origin: :imported,
      title:,
      source_excerpt:,
      source_fingerprint:,
      ai_summary: "Railsの非同期処理を解説します。",
      capabilities: [ "ジョブ実行" ],
      key_points: [ "PostgreSQLが必要" ],
      suggested_category_slugs:,
      suggested_tag_slugs:,
      summary_status: :succeeded,
      taxonomy_status:,
      review_status:
    )
  end

  def expected_input_sha(revision)
    Digest::SHA256.hexdigest(JSON.generate({
      title: revision.title,
      source_excerpt: revision.source_excerpt.to_s,
      summary: revision.ai_summary.to_s,
      capabilities: revision.capabilities,
      key_points: revision.key_points,
      taxonomy_registry_version: Taxonomy::Registry.version,
      taxonomy_registry_fingerprint: Taxonomy::Registry.vocabulary_fingerprint
    }))
  end
end
