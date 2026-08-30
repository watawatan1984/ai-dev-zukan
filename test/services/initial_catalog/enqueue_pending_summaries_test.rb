require "test_helper"

class InitialCatalog::EnqueuePendingSummariesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues the latest queued and failed revisions through the AI job" do
    queued = create_revision(kind: :mcp, status: :queued)
    failed = create_revision(kind: :skill, status: :failed)
    stale = create_revision(kind: :qiita_article, status: :processing)
    stale.update_column(:updated_at, 20.minutes.ago)
    create_revision(kind: :zenn_article, status: :succeeded)

    result = nil
    assert_enqueued_jobs 3, only: SummarizeRevisionJob do
      result = InitialCatalog::EnqueuePendingSummaries.call(target: 100)
    end

    assert_equal [ queued.id, failed.id, stale.id ], result.enqueued_revision_ids
    assert_enqueued_with(job: SummarizeRevisionJob, args: [ queued.id ])
    assert_enqueued_with(job: SummarizeRevisionJob, args: [ failed.id ])
    assert_enqueued_with(job: SummarizeRevisionJob, args: [ stale.id ])
  end

  private

  def create_revision(kind:, status:)
    uid = "#{kind}-#{status}"
    resource = Resource.create!(
      kind:,
      slug: uid,
      canonical_url: "https://example.com/#{uid}",
      normalized_canonical_url: "https://example.com/#{uid}",
      source_provider: kind.to_s.end_with?("article") ? kind.to_s.delete_suffix("_article") : :github,
      external_uid: uid
    )
    resource.revisions.create!(
      origin: :imported,
      title: uid,
      source_excerpt: "source",
      source_fingerprint: uid,
      ai_summary: ("日本語の要約" if status == :succeeded),
      summary_status: status,
      review_status: (status == :succeeded ? :review_pending : :draft)
    )
  end
end
