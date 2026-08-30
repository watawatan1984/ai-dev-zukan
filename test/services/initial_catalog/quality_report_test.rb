require "test_helper"

class InitialCatalog::QualityReportTest < ActiveSupport::TestCase
  test "accepts one complete Japanese summary per kind" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each do |kind|
      create_summarized_resource(kind:)
    end

    report = InitialCatalog::QualityReport.call(target: 1)

    assert report.acceptable?
    assert_equal 1, report.counts.dig("mcp", :summarized)
    assert_equal({ "test-model" => 1 }, report.counts.dig("qiita_article", :models))
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
  end
end
