require "test_helper"

class InitialCatalog::QualityReportTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "accepts one complete Japanese summary per kind" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each do |kind|
      create_summarized_resource(kind:)
    end

    report = InitialCatalog::QualityReport.call(target: 1)

    assert report.acceptable?
    assert_equal 1, report.counts.dig("mcp", :summarized)
    assert_equal 0, report.counts.dig("mcp", :taxonomy_v2_candidates)
    assert_equal({ "test-model" => 1 }, report.counts.dig("qiita_article", :models))
  end

  test "reports taxonomy v2 candidate readiness without changing initial release acceptability" do
    resource = create_summarized_resource(kind: :mcp)
    current = resource.revisions.last
    current.update!(review_status: :review_pending, suggested_category_slugs: [ "coding-development" ], suggested_tag_slugs: [ "ruby", "testing" ], taxonomy_status: :succeeded)
    Editorial::ApproveAndPublish.call(revision: current, reviewer: users(:admin))
    Taxonomy::BuildReclassificationCandidate.call(resource: resource.reload).update!(
      suggested_category_slugs: [ "automation-integration" ],
      suggested_tag_slugs: [ "ruby", "api-integration" ],
      taxonomy_status: :succeeded,
      taxonomy_confidence: 0.95
    )

    report = InitialCatalog::QualityReport.call(target: 1)

    assert_equal 1, report.counts.dig("mcp", :taxonomy_v2_candidates)
    assert_equal 1, report.counts.dig("mcp", :taxonomy_v2_succeeded)
  end

  test "rejects a catalog with a non Japanese summary" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each do |kind|
      summary = kind == :skill ? "English only summary" : "日本語の要約です。"
      create_summarized_resource(kind:, summary:)
    end

    report = InitialCatalog::QualityReport.call(target: 1)

    refute report.acceptable?
    assert_equal 1, report.counts.dig("skill", :non_japanese_summaries)
  end

  private

  def create_summarized_resource(kind:, summary: "日本語の要約です。")
    identifier = "report-#{kind}"
    provider = %i[mcp skill].include?(kind) ? :github : kind.to_s.delete_suffix("_article").to_sym
    resource = Resource.create!(
      kind: kind,
      slug: identifier,
      canonical_url: "https://example.com/#{identifier}",
      normalized_canonical_url: "https://example.com/#{identifier}",
      source_provider: provider,
      external_uid: identifier
    )
    resource.revisions.create!(
      origin: :imported,
      title: identifier,
      source_excerpt: "source excerpt",
      source_fingerprint: "fingerprint-#{identifier}",
      author_name: "author",
      ai_summary: summary,
      ai_model: "test-model",
      summary_status: :succeeded,
      review_status: :review_pending
    )
    resource
  end
end
