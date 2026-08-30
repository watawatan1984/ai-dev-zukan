module InitialCatalog
  class RepairQuality
    Result = Data.define(:trimmed_ids, :requeued_ids)

    def self.call
      new.call
    end

    def call
      trimmed_ids = []
      requeued_ids = []
      candidates.find_each do |revision|
        if japanese?(revision.ai_summary)
          next unless revision.ai_summary.length > 180

          revision.update!(ai_summary: revision.ai_summary.squish.truncate(180))
          trimmed_ids << revision.id
        else
          revision.update!(
            ai_summary: nil,
            capabilities: [],
            key_points: [],
            suggested_category_slug: nil,
            suggested_tag_slugs: [],
            ai_provider: nil,
            ai_model: nil,
            prompt_version: nil,
            summary_basis: nil,
            summary_generated_at: nil,
            summary_input_sha256: nil,
            summary_status: :failed,
            review_status: :draft
          )
          requeued_ids << revision.id
        end
      end
      Result.new(trimmed_ids:, requeued_ids:)
    end

    private

    def candidates
      latest_ids = InitialCatalog::Bootstrap::SOURCE_KINDS.values.flat_map do |kind|
        InitialCatalog::LatestRevisions.for_kind(kind).pluck(:id)
      end
      ResourceRevision
        .where(id: latest_ids)
        .where(summary_status: :succeeded, review_status: :review_pending)
        .where.not(ai_summary: [ nil, "" ])
    end

    def japanese?(summary)
      summary.match?(InitialCatalog::QualityReport::JAPANESE_TEXT)
    end
  end
end
