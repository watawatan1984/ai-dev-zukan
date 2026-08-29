module Ai
  class GenerateSummary
    def self.call(revision:, summarizer:)
      new(revision:, summarizer:).call
    end

    def initialize(revision:, summarizer:)
      @revision = revision
      @summarizer = summarizer
    end

    def call
      return revision unless claim_revision

      revision.reload
      result = summarizer.call(
        title: revision.title,
        source_excerpt: revision.source_excerpt
      )
      revision.update!(
        ai_summary: result.summary,
        capabilities: result.capabilities,
        key_points: result.key_points,
        suggested_category_slug: result.suggested_category_slug,
        suggested_tag_slugs: result.suggested_tag_slugs,
        ai_provider: result.provider,
        ai_model: result.model,
        prompt_version: result.prompt_version,
        summary_basis: result.basis,
        summary_input_sha256: Digest::SHA256.hexdigest(revision.source_excerpt.to_s),
        summary_generated_at: Time.current,
        summary_status: :succeeded,
        review_status: :review_pending
      )
      revision
    rescue StandardError
      revision.update_column(:summary_status, ResourceRevision.summary_statuses.fetch("failed")) if revision.persisted?
      raise
    end

    private

    attr_reader :revision, :summarizer

    def claim_revision
      ResourceRevision
        .where(id: revision.id, summary_status: [ :queued, :failed ])
        .update_all(summary_status: ResourceRevision.summary_statuses.fetch("processing")) == 1
    end
  end
end
