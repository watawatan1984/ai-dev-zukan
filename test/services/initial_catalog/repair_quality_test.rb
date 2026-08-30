require "test_helper"

class InitialCatalog::RepairQualityTest < ActiveSupport::TestCase
  test "trims long Japanese summaries and requeues non Japanese summaries" do
    long_revision = create_revision("長" * 240, identifier: "long")
    english_revision = create_revision("English only summary", identifier: "english")

    result = InitialCatalog::RepairQuality.call

    assert_includes result.trimmed_ids, long_revision.id
    assert_includes result.requeued_ids, english_revision.id
    assert_operator long_revision.reload.ai_summary.length, :<=, 180
    assert_predicate long_revision, :review_pending?
    assert_nil english_revision.reload.ai_summary
    assert_predicate english_revision, :summary_status_failed?
    assert_predicate english_revision, :draft?
  end

  private

  def create_revision(summary, identifier:)
    resource = Resource.create!(
      kind: :skill,
      slug: "repair-#{identifier}",
      canonical_url: "https://example.com/repair-#{identifier}",
      normalized_canonical_url: "https://example.com/repair-#{identifier}",
      source_provider: :github,
      external_uid: "repair-#{identifier}"
    )
    resource.revisions.create!(
      origin: :imported,
      title: identifier,
      source_excerpt: "source excerpt",
      source_fingerprint: "fingerprint-#{identifier}",
      ai_summary: summary,
      summary_status: :succeeded,
      review_status: :review_pending
    )
  end
end
