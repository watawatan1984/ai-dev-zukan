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
      records = review_candidates.map do |candidate|
        record_for(candidate, required_review: required_review_ids.include?(candidate.resource_id))
      end
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

    def review_candidates
      candidates_by_resource_id = scoped_candidates.index_by(&:resource_id)
      (base_resource_ids + required_review_ids).uniq.filter_map { |resource_id| candidates_by_resource_id[resource_id] }
    end

    def base_resource_ids
      @base_resource_ids ||= Resource.kinds.keys.flat_map do |kind|
        candidates_for_kind(kind).first(base_sample_per_kind).map(&:resource_id)
      end
    end

    def required_review_ids
      @required_review_ids ||= scoped_candidates.filter_map do |candidate|
        candidate.resource_id if required_review?(candidate)
      end
    end

    def candidates_for_kind(kind)
      scoped_candidates
        .select { |candidate| candidate.resource.kind == kind }
        .sort_by { |candidate| Digest::SHA256.hexdigest("taxonomy-v2:#{candidate.resource_id}") }
    end

    def scoped_candidates
      @scoped_candidates ||= scope.includes(:current_revision, :revisions).filter_map do |resource|
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
