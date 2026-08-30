require "digest"

module Taxonomy
  class ExportReviewSample
    CONFIDENCE_THRESHOLD = BigDecimal("0.90")
    DEFAULT_BASE_SAMPLE_PER_KIND = 20

    Result = Data.define(:path, :records_sha256, :record_count)

    def self.call(scope:, path:, base_sample_per_kind: DEFAULT_BASE_SAMPLE_PER_KIND)
      new(scope:, path:, base_sample_per_kind:).call
    end

    def initialize(scope:, path:, base_sample_per_kind:)
      @scope = scope
      @path = Pathname(path)
      @base_sample_per_kind = base_sample_per_kind.to_i
    end

    def call
      records = base_records + required_review_records
      records_sha256 = Digest::SHA256.hexdigest(JSON.generate(records))
      payload = {
        format: "ai-dev-zukan.taxonomy-review",
        version: 1,
        taxonomy_version: Taxonomy::BuildReclassificationCandidate::TAXONOMY_VERSION,
        generated_at: Time.current.iso8601,
        records_sha256:,
        records:
      }

      FileUtils.mkdir_p(path.dirname)
      File.write(path, JSON.pretty_generate(payload))
      Result.new(path: path.to_s, records_sha256:, record_count: records.size)
    end

    private

    attr_reader :scope, :path, :base_sample_per_kind

    def base_records
      Resource.kinds.keys.flat_map do |kind|
        candidates_for_kind(kind)
          .sort_by { |candidate| Digest::SHA256.hexdigest("taxonomy-v2:#{candidate.resource_id}") }
          .first(base_sample_per_kind)
          .map { |candidate| record_for(candidate, required_review: false) }
      end
    end

    def required_review_records
      scope.includes(:current_revision, :revisions).flat_map do |resource|
        candidate = taxonomy_candidate_for(resource)
        next [] unless candidate && required_review?(candidate)

        [ record_for(candidate, required_review: true) ]
      end
    end

    def candidates_for_kind(kind)
      scope.where(kind:).includes(:current_revision, :revisions).filter_map do |resource|
        taxonomy_candidate_for(resource)
      end
    end

    def taxonomy_candidate_for(resource)
      current = resource.current_revision
      return unless current

      resource.revisions.find do |revision|
        revision.source_fingerprint == Digest::SHA256.hexdigest("#{current.source_fingerprint}:taxonomy-v2")
      end
    end

    def required_review?(candidate)
      candidate.taxonomy_status_failed? ||
        candidate.taxonomy_confidence.to_d < CONFIDENCE_THRESHOLD ||
        !Taxonomy::ValidateSuggestion.call(revision: candidate).valid?
    end

    def record_for(candidate, required_review:)
      {
        resource_id: candidate.resource_id,
        kind: candidate.resource.kind,
        title: candidate.title,
        category_slugs: candidate.suggested_category_slugs,
        tag_slugs: candidate.suggested_tag_slugs,
        confidence: candidate.taxonomy_confidence&.to_f,
        required_review:,
        category_match: nil,
        tag_match: nil,
        review_note: nil
      }
    end
  end
end
