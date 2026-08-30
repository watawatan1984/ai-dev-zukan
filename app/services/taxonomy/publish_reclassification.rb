require "digest"

module Taxonomy
  class PublishReclassification
    ConfirmationRequired = Class.new(StandardError)
    ReviewerNotAuthorized = Class.new(StandardError)
    QualityGateFailed = Class.new(StandardError)

    CONFIRMATION = "publish-taxonomy-v2"

    Result = Data.define(:published_resource_ids)

    def self.call(reviewer:, confirmation:, review_path:, scope: Resource.publicly_visible, target_per_kind: Taxonomy::QualityReport::DEFAULT_TARGET_PER_KIND)
      new(reviewer:, confirmation:, review_path:, scope:, target_per_kind:).call
    end

    def initialize(reviewer:, confirmation:, review_path:, scope:, target_per_kind:)
      @reviewer = reviewer
      @confirmation = confirmation
      @review_path = review_path
      @scope = scope
      @target_per_kind = target_per_kind
    end

    def call
      raise ConfirmationRequired, "Set CONFIRM=publish-taxonomy-v2 to publish taxonomy v2" unless confirmation == CONFIRMATION
      unless reviewer&.admin? && reviewer.locked_at.present? && reviewer.email.to_s.end_with?(".invalid")
        raise ReviewerNotAuthorized, "Taxonomy v2 publication requires a locked .invalid admin reviewer"
      end

      quality_report = Taxonomy::QualityReport.call(scope:, review_path:, target_per_kind:)
      raise QualityGateFailed, quality_report.errors.join("; ") unless quality_report.acceptable?

      candidates = preflight_candidates
      published_resource_ids = []
      Resource.transaction do
        candidates.each do |candidate|
          Editorial::ApproveAndPublish.call(
            revision: candidate,
            reviewer:,
            request_id: "catalog-taxonomy-v2"
          )
          published_resource_ids << candidate.resource_id
        end
      end

      Result.new(published_resource_ids:)
    end

    private

    attr_reader :reviewer, :confirmation, :review_path, :scope, :target_per_kind

    def preflight_candidates
      candidates = scope.includes(:current_revision, :revisions).map do |resource|
        candidate = taxonomy_candidate_for(resource)
        unless candidate&.review_pending? && candidate.ai_summary.present?
          raise QualityGateFailed, "resource #{resource.id} candidate is not ready for publication"
        end

        validation = Taxonomy::ValidateSuggestion.call(revision: candidate)
        raise QualityGateFailed, "resource #{resource.id} taxonomy invalid: #{validation.errors.join(', ')}" unless validation.valid?

        candidate
      end

      raise QualityGateFailed, "no taxonomy-v2 candidates to publish" if candidates.empty?

      candidates
    end

    def taxonomy_candidate_for(resource)
      current = resource.current_revision
      return unless current

      resource.revisions.find do |revision|
        revision.source_fingerprint == Digest::SHA256.hexdigest("#{current.source_fingerprint}:taxonomy-v2")
      end
    end
  end
end
