require "digest"

module Taxonomy
  class GenerateSuggestion
    class InvalidSuggestion < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super(errors.join(", "))
      end
    end

    CLAIMABLE_STATUSES = %i[not_requested queued failed].freeze

    def self.call(revision:, taxonomizer: Ai::NvidiaTaxonomizer.new)
      new(revision:, taxonomizer:).call
    end

    def initialize(revision:, taxonomizer:)
      @revision = revision
      @taxonomizer = taxonomizer
    end

    def call
      return revision unless claim_revision

      revision.reload
      result = taxonomizer.call(revision:)
      persist_result(result)
      revision
    rescue InvalidSuggestion
      mark_failed
      raise
    rescue StandardError
      mark_failed if revision.persisted?
      raise
    end

    private

    attr_reader :revision, :taxonomizer

    def claim_revision
      ResourceRevision
        .where(id: revision.id, review_status: non_approved_review_statuses, taxonomy_status: CLAIMABLE_STATUSES)
        .update_all(
          taxonomy_status: ResourceRevision.taxonomy_statuses.fetch("processing"),
          taxonomy_input_sha256: input_sha256,
          updated_at: Time.current
        ) == 1
    end

    def persist_result(result)
      validation = Taxonomy::ValidateSuggestion.call(revision: validation_revision(result))
      raise InvalidSuggestion, validation.errors unless validation.valid?

      revision.update!(
        suggested_category_slugs: validation.category_slugs,
        suggested_tag_slugs: validation.tag_slugs,
        search_keywords: validation.search_keywords,
        taxonomy_confidence: result.confidence,
        taxonomy_provider: result.provider,
        taxonomy_model: result.model,
        taxonomy_prompt_version: result.prompt_version,
        taxonomy_origin: :ai,
        taxonomy_generated_at: Time.current,
        taxonomy_status: :succeeded
      )
    end

    def validation_revision(result)
      revision.dup.tap do |candidate|
        candidate.resource = revision.resource
        candidate.suggested_category_slugs = result.category_slugs
        candidate.suggested_tag_slugs = result.tag_slugs
        candidate.search_keywords = result.search_keywords
      end
    end

    def input_sha256
      Digest::SHA256.hexdigest(JSON.generate({
        title: revision.title,
        source_excerpt: revision.source_excerpt.to_s,
        summary: revision.ai_summary.to_s,
        capabilities: revision.capabilities,
        key_points: revision.key_points,
        taxonomy_registry_version: Taxonomy::Registry.version,
        taxonomy_registry_fingerprint: Taxonomy::Registry.vocabulary_fingerprint
      }))
    end

    def mark_failed
      ResourceRevision
        .where(id: revision.id, review_status: non_approved_review_statuses)
        .update_all(
          taxonomy_status: ResourceRevision.taxonomy_statuses.fetch("failed"),
          updated_at: Time.current
        )
    end

    def non_approved_review_statuses
      ResourceRevision.review_statuses.except("approved").values
    end
  end
end
