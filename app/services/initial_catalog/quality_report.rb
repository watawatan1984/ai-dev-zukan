require "digest"

module InitialCatalog
  class QualityReport
    JAPANESE_TEXT = /[ぁ-んァ-ヶ一-龠々]/

    Result = Data.define(:target, :counts) do
      def acceptable?
        counts.values.all? do |metrics|
          metrics.fetch(:resources) >= target &&
            metrics.fetch(:summarized) >= target &&
            metrics.fetch(:review_pending) + metrics.fetch(:published) >= target &&
            metrics.fetch(:blank_summaries).zero? &&
            metrics.fetch(:non_japanese_summaries).zero? &&
            metrics.fetch(:overlong_summaries).zero?
        end
      end
    end

    def self.call(target: InitialCatalog::Bootstrap::MAX_LIMIT)
      new(target:).call
    end

    def initialize(target:)
      @target = target.to_i.clamp(1, InitialCatalog::Bootstrap::MAX_LIMIT)
    end

    def call
      Result.new(target:, counts: counts)
    end

    private

    attr_reader :target

    def counts
      InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with do |kind|
        resource_scope = Resource.where(
          kind: kind,
          publication_status: InitialCatalog::LatestRevisions.active_publication_statuses
        )
        summarized = summarized_scope(kind)
        summaries = summarized.pluck(:ai_summary)
        {
          resources: resource_scope.count,
          summarized: summarized.distinct.count(:resource_id),
          review_pending: summarized.review_pending.distinct.count(:resource_id),
          published: resource_scope.published.count,
          blank_summaries: summaries.count(&:blank?),
          non_japanese_summaries: summaries.count { |summary| summary.present? && !summary.match?(JAPANESE_TEXT) },
          overlong_summaries: summaries.count { |summary| summary.to_s.length > 180 },
          blank_excerpts: summarized.where(source_excerpt: [ nil, "" ]).count,
          missing_authors: summarized.where(author_name: [ nil, "" ]).count,
          taxonomy_v2_candidates: taxonomy_v2_candidates(resource_scope),
          taxonomy_v2_succeeded: taxonomy_v2_succeeded(resource_scope),
          models: summarized.group(:ai_model).count
        }
      end.transform_keys(&:to_s)
    end

    def summarized_scope(kind)
      InitialCatalog::LatestRevisions
        .for_kind(kind)
        .where(summary_status: :succeeded)
    end

    def taxonomy_v2_candidates(resource_scope)
      resource_scope.includes(:current_revision, :revisions).count do |resource|
        taxonomy_v2_candidate_for(resource).present?
      end
    end

    def taxonomy_v2_succeeded(resource_scope)
      resource_scope.includes(:current_revision, :revisions).count do |resource|
        taxonomy_v2_candidate_for(resource)&.taxonomy_status_succeeded?
      end
    end

    def taxonomy_v2_candidate_for(resource)
      current = resource.current_revision
      return unless current

      fingerprint = Digest::SHA256.hexdigest("#{current.source_fingerprint}:taxonomy-v2")
      resource.revisions.find { |revision| revision.source_fingerprint == fingerprint }
    end
  end
end
