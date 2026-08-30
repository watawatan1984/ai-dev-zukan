require "digest"

module Taxonomy
  class QualityReport
    DEFAULT_TARGET_PER_KIND = 100
    DEFAULT_BASE_SAMPLE_PER_KIND = 20
    ACCURACY_THRESHOLD = 0.90

    Result = Data.define(:target_per_kind, :counts, :errors, :category_accuracy, :tag_accuracy) do
      def acceptable?
        errors.empty? && category_accuracy >= ACCURACY_THRESHOLD && tag_accuracy >= ACCURACY_THRESHOLD
      end
    end

    def self.call(scope:, review_path:, target_per_kind: DEFAULT_TARGET_PER_KIND, base_sample_per_kind: DEFAULT_BASE_SAMPLE_PER_KIND)
      new(scope:, review_path:, target_per_kind:, base_sample_per_kind:).call
    end

    def initialize(scope:, review_path:, target_per_kind:, base_sample_per_kind:)
      @scope = scope
      @review_path = Pathname(review_path)
      @target_per_kind = target_per_kind.to_i
      @base_sample_per_kind = base_sample_per_kind.to_i
      @errors = []
    end

    def call
      candidates = candidates_by_resource_id
      validate_candidate_presence(candidates)
      validate_candidates(candidates.values)
      records = review_records
      validate_artifact_records(records, candidates)
      validate_required_reviews(records)
      category_accuracy = accuracy(records, "category_match")
      tag_accuracy = accuracy(records, "tag_match")
      errors << "category accuracy below 90%: #{format_accuracy(category_accuracy)}" if category_accuracy < ACCURACY_THRESHOLD
      errors << "tag accuracy below 90%: #{format_accuracy(tag_accuracy)}" if tag_accuracy < ACCURACY_THRESHOLD

      Result.new(
        target_per_kind:,
        counts: counts(candidates.values),
        errors:,
        category_accuracy:,
        tag_accuracy:
      )
    end

    private

    attr_reader :scope, :review_path, :target_per_kind, :base_sample_per_kind, :errors

    def candidates_by_resource_id
      scope.includes(:current_revision, :revisions).index_with do |resource|
        current = resource.current_revision
        next unless current

        resource.revisions.find do |revision|
          revision.source_fingerprint == Digest::SHA256.hexdigest("#{current.source_fingerprint}:taxonomy-v2")
        end
      end.compact.transform_keys(&:id)
    end

    def validate_candidate_presence(candidates)
      Resource.kinds.keys.each do |kind|
        count = scope.where(kind:).count { |resource| candidates.key?(resource.id) }
        errors << "#{kind} has #{count} taxonomy-v2 candidates; expected at least #{target_per_kind}" if count < target_per_kind
      end

      scope.find_each do |resource|
        errors << "resource #{resource.id} is missing taxonomy-v2 candidate" unless candidates.key?(resource.id)
      end
    end

    def validate_candidates(candidates)
      candidates.each do |candidate|
        errors << "resource #{candidate.resource_id} taxonomy status is #{candidate.taxonomy_status}" unless candidate.taxonomy_status_succeeded?
        validation = Taxonomy::ValidateSuggestion.call(revision: candidate)
        next if validation.valid?

        errors << "resource #{candidate.resource_id} taxonomy invalid: #{validation.errors.join(', ')}"
      end
    end

    def review_records
      payload = JSON.parse(File.read(review_path))
      unless payload.fetch("format") == "ai-dev-zukan.taxonomy-review" &&
          payload.fetch("version") == 1 &&
          payload.fetch("taxonomy_version") == "taxonomy-v2"
        errors << "review artifact metadata is invalid"
      end

      records = payload.fetch("records")
      expected_sha = Digest::SHA256.hexdigest(JSON.generate(records))
      errors << "review records checksum does not match" unless payload.fetch("records_sha256") == expected_sha
      records
    rescue Errno::ENOENT
      errors << "review artifact not found: #{review_path}"
      []
    rescue JSON::ParserError, KeyError => error
      errors << "review artifact invalid: #{error.message}"
      []
    end

    def validate_required_reviews(records)
      records.select { |record| record.fetch("required_review") }.each do |record|
        next if boolean?(record["category_match"]) && boolean?(record["tag_match"])

        errors << "required review incomplete for resource #{record.fetch('resource_id')}"
      end
    end

    def accuracy(records, field)
      records_by_id = records.index_by { |record| record.fetch("resource_id") }
      base_records = base_resource_ids.filter_map { |resource_id| records_by_id[resource_id] }
      return 0.0 if base_records.empty?

      base_records.count { |record| record[field] == true }.fdiv(base_records.size)
    end

    def validate_artifact_records(records, candidates)
      validate_resource_ids(records)
      expected_by_id = expected_records(candidates)
      records.each do |record|
        validate_decisions(record)
        expected = expected_by_id[record.fetch("resource_id")]
        next unless expected

        validate_canonical_data(record, expected)
      end
    end

    def validate_resource_ids(records)
      ids = records.map { |record| record.fetch("resource_id") }
      errors << "duplicate artifact record ids" if ids.uniq.size != ids.size
      errors << "missing artifact record ids" if (expected_resource_ids - ids).any?
      errors << "extra artifact record ids" if (ids - expected_resource_ids).any?
      if (expected_resource_ids - ids).any? && (ids - expected_resource_ids).any?
        errors << "substituted artifact record ids"
      end
    end

    def validate_decisions(record)
      %w[category_match tag_match].each do |field|
        next if boolean?(record[field])

        errors << "resource #{record.fetch('resource_id')} #{field} must be boolean"
      end
    end

    def validate_canonical_data(record, expected)
      if expected["required_review"] == true && record["required_review"] != true
        errors << "resource #{record.fetch('resource_id')} required_review must be true"
        return
      end

      %w[kind title category_slugs tag_slugs confidence required_review].each do |field|
        next if record[field] == expected[field]

        errors << "resource #{record.fetch('resource_id')} #{field} does not match current candidate"
      end
    end

    def expected_records(candidates)
      candidates.slice(*expected_resource_ids).transform_values do |candidate|
        expected_record_for(candidate, required_review: required_resource_ids.include?(candidate.resource_id))
      end
    end

    def expected_resource_ids
      @expected_resource_ids ||= (base_resource_ids + required_resource_ids).uniq
    end

    def base_resource_ids
      @base_resource_ids ||= Resource.kinds.keys.flat_map do |kind|
        candidates_by_resource_id.values
          .select { |candidate| candidate.resource.kind == kind }
          .sort_by { |candidate| Digest::SHA256.hexdigest("taxonomy-v2:#{candidate.resource_id}") }
          .first(base_sample_per_kind)
          .map(&:resource_id)
      end
    end

    def required_resource_ids
      @required_resource_ids ||= candidates_by_resource_id.values.filter_map do |candidate|
        candidate.resource_id if required_review?(candidate)
      end
    end

    def required_review?(candidate)
      candidate.taxonomy_status_failed? ||
        candidate.taxonomy_confidence.to_d < BigDecimal("0.90") ||
        !Taxonomy::ValidateSuggestion.call(revision: candidate).valid?
    end

    def expected_record_for(candidate, required_review:)
      {
        "resource_id" => candidate.resource_id,
        "kind" => candidate.resource.kind,
        "title" => candidate.title,
        "category_slugs" => candidate.suggested_category_slugs,
        "tag_slugs" => candidate.suggested_tag_slugs,
        "confidence" => candidate.taxonomy_confidence&.to_f,
        "required_review" => required_review
      }
    end

    def boolean?(value)
      value == true || value == false
    end

    def counts(candidates)
      Resource.kinds.keys.index_with do |kind|
        kind_candidates = candidates.select { |candidate| candidate.resource.kind == kind }
        {
          candidates: kind_candidates.size,
          succeeded: kind_candidates.count(&:taxonomy_status_succeeded?)
        }
      end
    end

    def format_accuracy(value)
      "#{(value * 100).round(1)}%"
    end
  end
end
