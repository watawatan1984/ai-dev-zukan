module InitialCatalog
  class ExportSnapshot
    FORMAT = "ai-dev-zukan.initial-catalog"
    VERSION = 1
    InvalidCatalog = Class.new(StandardError)
    Result = Data.define(:path, :counts, :checksum)

    def self.call(path:, target: Bootstrap::MAX_LIMIT)
      new(path:, target:).call
    end

    def initialize(path:, target:)
      @path = Pathname(path)
      @target = target.to_i.clamp(1, Bootstrap::MAX_LIMIT)
    end

    def call
      report = QualityReport.call(target:)
      raise InvalidCatalog, "Initial catalog quality gate failed" unless report.acceptable?

      records = serialized_records
      counts = records.group_by { |record| record.dig("resource", "kind") }.transform_values(&:count)
      checksum = Digest::SHA256.hexdigest(JSON.generate(records))
      payload = {
        "format" => FORMAT,
        "version" => VERSION,
        "target" => target,
        "counts" => counts,
        "records_sha256" => checksum,
        "records" => records
      }
      path.dirname.mkpath
      path.write(JSON.pretty_generate(payload) << "\n")
      Result.new(path: path.to_s, counts:, checksum:)
    end

    private

    attr_reader :path, :target

    def serialized_records
      Bootstrap::SOURCE_KINDS.values.flat_map do |kind|
        export_scope(kind).map { |revision| serialize(revision) }
      end
    end

    def export_scope(kind)
      LatestRevisions
        .for_kind(kind)
        .where(summary_status: :succeeded)
        .where(review_status: [ :review_pending, :approved ])
        .includes(:resource)
        .order(Arel.sql("resources.popularity_score DESC"), "resources.id")
        .limit(target)
    end

    def serialize(revision)
      resource = revision.resource
      {
        "resource" => {
          "kind" => resource.kind,
          "provider" => resource.source_provider,
          "external_uid" => resource.external_uid,
          "canonical_url" => resource.canonical_url,
          "source_published_at" => iso8601(resource.source_published_at),
          "source_updated_at" => iso8601(resource.source_updated_at),
          "popularity_raw" => resource.popularity_raw
        },
        "revision" => {
          "title" => revision.title,
          "author_name" => revision.author_name,
          "source_excerpt" => revision.source_excerpt,
          "source_fingerprint" => revision.source_fingerprint,
          "ai_summary" => revision.ai_summary,
          "capabilities" => revision.capabilities,
          "key_points" => revision.key_points,
          "suggested_category_slug" => revision.suggested_category_slug,
          "suggested_tag_slugs" => revision.suggested_tag_slugs,
          "ai_provider" => revision.ai_provider,
          "ai_model" => revision.ai_model,
          "prompt_version" => revision.prompt_version,
          "summary_basis" => revision.summary_basis,
          "summary_input_sha256" => revision.summary_input_sha256,
          "summary_generated_at" => iso8601(revision.summary_generated_at)
        }
      }
    end

    def iso8601(value)
      value&.iso8601(6)
    end
  end
end
