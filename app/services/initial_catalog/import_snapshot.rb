module InitialCatalog
  class ImportSnapshot
    InvalidSnapshot = Class.new(StandardError)
    Result = Data.define(:target, :created_revisions, :unchanged_revisions, :counts)

    def self.call(path:, target: Bootstrap::MAX_LIMIT)
      new(path:, target:).call
    end

    def initialize(path:, target:)
      @path = Pathname(path)
      @target = target.to_i.clamp(1, Bootstrap::MAX_LIMIT)
    end

    def call
      payload = JSON.parse(path.read)
      records = validate!(payload)
      counts = Hash.new(0)
      Resource.transaction do
        records.each do |record|
          result = import(record)
          counts[result] += 1
        end
      end
      Result.new(
        target:,
        created_revisions: counts[:created_revision],
        unchanged_revisions: counts[:unchanged],
        counts: payload.fetch("counts")
      )
    end

    private

    attr_reader :path, :target

    def validate!(payload)
      raise InvalidSnapshot, "Unexpected snapshot format" unless payload["format"] == ExportSnapshot::FORMAT
      raise InvalidSnapshot, "Unsupported snapshot version" unless payload["version"] == ExportSnapshot::VERSION
      raise InvalidSnapshot, "Snapshot target does not match" unless payload["target"] == target

      records = payload.fetch("records")
      checksum = Digest::SHA256.hexdigest(JSON.generate(records))
      raise InvalidSnapshot, "Snapshot checksum does not match" unless checksum == payload["records_sha256"]

      actual_counts = records.group_by { |record| record.dig("resource", "kind") }.transform_values(&:count)
      expected_counts = Bootstrap::SOURCE_KINDS.values.index_with { target }.transform_keys(&:to_s)
      unless actual_counts == expected_counts && payload["counts"] == expected_counts
        raise InvalidSnapshot, "Snapshot must contain exactly #{target} records for every kind"
      end

      records
    rescue KeyError, JSON::ParserError => error
      raise InvalidSnapshot, error.message
    end

    def import(record)
      resource_data = record.fetch("resource")
      revision_data = record.fetch("revision")
      result = Ingestion::UpsertSnapshot.call(snapshot: build_snapshot(resource_data, revision_data))
      apply_summary(result.revision, revision_data)
      reactivate(result.resource)
      result.status
    end

    def build_snapshot(resource, revision)
      Sources::Snapshot.new(
        kind: resource.fetch("kind"),
        provider: resource.fetch("provider"),
        external_uid: resource.fetch("external_uid"),
        canonical_url: resource.fetch("canonical_url"),
        title: revision.fetch("title"),
        author_name: revision["author_name"],
        excerpt: revision.fetch("source_excerpt"),
        source_fingerprint: revision.fetch("source_fingerprint"),
        source_published_at: parse_time(resource["source_published_at"]),
        source_updated_at: parse_time(resource["source_updated_at"]),
        popularity_raw: resource.fetch("popularity_raw")
      )
    end

    def apply_summary(revision, attributes)
      return if revision.approved?

      revision.update!(
        ai_summary: attributes.fetch("ai_summary"),
        capabilities: attributes.fetch("capabilities"),
        key_points: attributes.fetch("key_points"),
        suggested_category_slug: attributes["suggested_category_slug"],
        suggested_tag_slugs: attributes.fetch("suggested_tag_slugs"),
        ai_provider: attributes.fetch("ai_provider"),
        ai_model: attributes.fetch("ai_model"),
        prompt_version: attributes.fetch("prompt_version"),
        summary_basis: attributes.fetch("summary_basis"),
        summary_input_sha256: attributes.fetch("summary_input_sha256"),
        summary_generated_at: parse_time(attributes["summary_generated_at"]),
        summary_status: :succeeded,
        review_status: :review_pending
      )
    end

    def reactivate(resource)
      return unless resource.archived?

      resource.update!(publication_status: :unpublished, archived_at: nil)
    end

    def parse_time(value)
      Time.iso8601(value) if value.present?
    end
  end
end
