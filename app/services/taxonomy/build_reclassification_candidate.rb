require "digest"

module Taxonomy
  class BuildReclassificationCandidate
    TAXONOMY_VERSION = "taxonomy-v2"

    def self.call(resource:)
      new(resource:).call
    end

    def initialize(resource:)
      @resource = resource
    end

    def call
      current = resource.current_revision
      raise ActiveRecord::RecordNotFound, "Resource has no current approved revision" unless current&.approved?

      ResourceRevision.find_or_create_by!(resource:, source_fingerprint: fingerprint_for(current)) do |candidate|
        candidate.assign_attributes(candidate_attributes(current))
      end
    end

    private

    attr_reader :resource

    def fingerprint_for(revision)
      Digest::SHA256.hexdigest("#{revision.source_fingerprint}:#{TAXONOMY_VERSION}")
    end

    def candidate_attributes(revision)
      {
        origin: revision.origin,
        title: revision.title,
        source_excerpt: revision.source_excerpt,
        author_name: revision.author_name,
        ai_summary: revision.ai_summary,
        ai_provider: revision.ai_provider,
        ai_model: revision.ai_model,
        prompt_version: revision.prompt_version,
        summary_basis: revision.summary_basis,
        summary_input_sha256: revision.summary_input_sha256,
        summary_generated_at: revision.summary_generated_at,
        capabilities: revision.capabilities,
        key_points: revision.key_points,
        summary_status: :succeeded,
        taxonomy_status: :queued,
        taxonomy_origin: :ai,
        review_status: :draft
      }
    end
  end
end
