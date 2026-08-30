module InitialCatalog
  class EnqueuePendingSummaries
    STALE_PROCESSING_AFTER = 15.minutes
    Result = Data.define(:target, :enqueued_revision_ids)

    def self.call(target: Bootstrap::MAX_LIMIT, stale_after: STALE_PROCESSING_AFTER)
      new(target:, stale_after:).call
    end

    def initialize(target:, stale_after:)
      @target = target.to_i.clamp(1, Bootstrap::MAX_LIMIT)
      @stale_after = stale_after
    end

    def call
      recover_stale_processing
      revision_ids = Bootstrap::SOURCE_KINDS.values.flat_map do |kind|
        pending_scope(kind).limit(target).pluck(:id)
      end
      revision_ids.each { |revision_id| SummarizeRevisionJob.perform_later(revision_id) }
      Result.new(target:, enqueued_revision_ids: revision_ids)
    end

    private

    attr_reader :target, :stale_after

    def recover_stale_processing
      latest_ids = Bootstrap::SOURCE_KINDS.values.flat_map do |kind|
        LatestRevisions.for_kind(kind).pluck(:id)
      end
      ResourceRevision
        .where(id: latest_ids, summary_status: :processing)
        .where(updated_at: ...stale_after.ago)
        .update_all(
          summary_status: ResourceRevision.summary_statuses.fetch("failed"),
          updated_at: Time.current
        )
    end

    def pending_scope(kind)
      LatestRevisions
        .for_kind(kind)
        .where(summary_status: [ :queued, :failed ])
        .where(review_status: [ :draft, :review_pending ])
        .order(:id)
    end
  end
end
