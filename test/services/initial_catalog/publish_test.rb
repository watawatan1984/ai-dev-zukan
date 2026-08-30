require "test_helper"

class InitialCatalog::PublishTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "requires explicit confirmation and publishes an atomic reviewed batch" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each do |kind|
      2.times { |index| create_candidate(kind:, index:) }
    end

    assert_raises(InitialCatalog::Publish::ConfirmationRequired) do
      InitialCatalog::Publish.call(
        reviewer: users(:admin),
        confirmation: "",
        limit: 2
      )
    end

    result = InitialCatalog::Publish.call(
      reviewer: users(:admin),
      confirmation: "publish",
      limit: 2
    )

    assert result.complete?
    assert_equal 8, Resource.published.count
    assert_equal 8, ResourceRevision.approved.count
    assert_equal 8, AdminAuditLog.where(action: "resource_revision.approve_and_publish").count
  end

  test "does not partially publish when one kind is below target" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each do |kind|
      count = kind == :qiita_article ? 1 : 2
      count.times { |index| create_candidate(kind:, index:) }
    end

    assert_raises(InitialCatalog::Publish::IncompleteCatalog) do
      InitialCatalog::Publish.call(
        reviewer: users(:admin),
        confirmation: "publish",
        limit: 2
      )
    end
    assert_equal 0, Resource.published.count
  end

  private

  def create_candidate(kind:, index:)
    identifier = "#{kind}-#{index}"
    provider = %i[mcp skill].include?(kind) ? :github : kind.to_s.delete_suffix("_article").to_sym
    resource = Resource.create!(
      kind: kind,
      slug: identifier,
      canonical_url: "https://example.com/#{identifier}",
      normalized_canonical_url: "https://example.com/#{identifier}",
      source_provider: provider,
      external_uid: identifier,
      popularity_score: index
    )
    resource.revisions.create!(
      origin: :imported,
      title: identifier,
      source_fingerprint: "fingerprint-#{identifier}",
      ai_summary: "#{identifier}の要約です。",
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "ruby", "testing" ],
      summary_status: :succeeded,
      review_status: :review_pending
    )
  end
end
