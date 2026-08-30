module InitialCatalog
  class ImportSnapshot
    InvalidSnapshot = Class.new(StandardError)
    SUPPORTED_VERSIONS = [ 1, 2 ].freeze
    RESOURCE_KEYS = %w[
      kind provider external_uid canonical_url source_published_at source_updated_at popularity_raw
    ].freeze
    SUMMARY_REVISION_KEYS = %w[
      title source_excerpt source_fingerprint ai_summary capabilities key_points suggested_tag_slugs
      ai_provider ai_model prompt_version summary_basis summary_input_sha256 summary_generated_at
    ].freeze
    V1_REVISION_KEYS = (SUMMARY_REVISION_KEYS + %w[suggested_category_slug]).freeze
    V2_REVISION_KEYS = (SUMMARY_REVISION_KEYS + %w[
      suggested_category_slugs search_keywords taxonomy_status taxonomy_origin taxonomy_provider
      taxonomy_model taxonomy_prompt_version taxonomy_input_sha256 taxonomy_generated_at taxonomy_confidence
    ]).freeze
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
      snapshot = validate!(payload)
      counts = Hash.new(0)
      Resource.transaction do
        sync_vocabulary(snapshot.fetch(:taxonomy)) if snapshot.fetch(:version) == 2
        snapshot.fetch(:records).each do |record|
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
      version = Integer(payload.fetch("version"))
      raise InvalidSnapshot, "Unsupported snapshot version" unless SUPPORTED_VERSIONS.include?(version)
      raise InvalidSnapshot, "Snapshot target does not match" unless payload["target"] == target

      records = payload.fetch("records")
      raise InvalidSnapshot, "Snapshot records must be an array" unless records.is_a?(Array)

      checksum = Digest::SHA256.hexdigest(JSON.generate(records))
      raise InvalidSnapshot, "Snapshot checksum does not match" unless checksum == payload["records_sha256"]
      taxonomy = validate_taxonomy!(payload, version)

      actual_counts = records.group_by { |record| record.dig("resource", "kind") }.transform_values(&:count)
      expected_counts = Bootstrap::SOURCE_KINDS.values.index_with { target }.transform_keys(&:to_s)
      unless actual_counts == expected_counts && payload["counts"] == expected_counts
        raise InvalidSnapshot, "Snapshot must contain exactly #{target} records for every kind"
      end

      normalized_records = records.map do |record|
        version == 1 ? normalize_v1_record(record) : normalize_v2_record(record, taxonomy)
      end
      { version:, taxonomy:, records: normalized_records }
    rescue ArgumentError, KeyError, JSON::ParserError => error
      raise InvalidSnapshot, error.message
    end

    def validate_taxonomy!(payload, version)
      return if version == 1

      taxonomy = payload.fetch("taxonomy")
      raise InvalidSnapshot, "Snapshot taxonomy must be an object" unless taxonomy.is_a?(Hash)

      checksum = Digest::SHA256.hexdigest(JSON.generate(taxonomy))
      raise InvalidSnapshot, "Snapshot taxonomy checksum does not match" unless checksum == payload["taxonomy_sha256"]
      raise InvalidSnapshot, "Unexpected taxonomy version" unless taxonomy.fetch("version") == Taxonomy::Registry.version
      unless taxonomy.fetch("tag_groups") == Taxonomy::Registry.definition.fetch("tag_groups")
        raise InvalidSnapshot, "Snapshot tag groups do not match the controlled taxonomy"
      end
      unless taxonomy.fetch("categories") == Taxonomy::Registry.definition.fetch("categories")
        raise InvalidSnapshot, "Snapshot categories do not match the fixed taxonomy"
      end

      validate_declared_tags!(taxonomy.fetch("tags"))
      taxonomy
    end

    def validate_declared_tags!(tags)
      raise InvalidSnapshot, "Snapshot tags must be an array" unless tags.is_a?(Array)

      groups = Taxonomy::Registry.definition.fetch("tag_groups").keys
      tag_slugs = []
      aliases = []
      tags.each do |tag|
        raise InvalidSnapshot, "Snapshot tag must be an object" unless tag.is_a?(Hash)
        slug = normalize_identifier(tag.fetch("slug"))
        normalized_name = Taxonomy::Registry.normalize(slug)
        raise InvalidSnapshot, "Blank tag slug" if slug.blank?
        raise InvalidSnapshot, "Snapshot tag slug must be normalized: #{tag.fetch('slug')}" unless slug == tag.fetch("slug")
        raise InvalidSnapshot, "Unknown tag group: #{tag.fetch('group')}" unless groups.include?(tag.fetch("group"))
        raise InvalidSnapshot, "Snapshot tag must be active: #{slug}" unless tag.fetch("active") == true
        raise InvalidSnapshot, "Snapshot tag name is blank: #{slug}" if tag.fetch("name").blank?
        raise InvalidSnapshot, "Snapshot tag filterable must be boolean: #{slug}" unless [ true, false ].include?(tag.fetch("filterable"))
        Integer(tag.fetch("position"))
        raise InvalidSnapshot, "Snapshot tag alias list must be an array: #{slug}" unless tag.fetch("aliases").is_a?(Array)

        tag_slugs << slug
        tag.fetch("aliases").each do |alias_name|
          raise InvalidSnapshot, "Snapshot tag alias must be a string: #{slug}" unless alias_name.is_a?(String)

          normalized_alias = Taxonomy::Registry.normalize(alias_name)
          raise InvalidSnapshot, "Snapshot tag alias is blank: #{slug}" if alias_name.blank? || normalized_alias.blank?

          aliases << normalized_alias
        end
        raise InvalidSnapshot, "Snapshot tag normalized name conflict: #{slug}" unless normalized_name == slug
      end

      reject_duplicates!(tag_slugs, "tag slug")
      reject_duplicates!(aliases, "tag alias")
      collision = aliases.find { |alias_name| tag_slugs.include?(alias_name) }
      raise InvalidSnapshot, "Snapshot alias collides with tag slug: #{collision}" if collision
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
        suggested_category_slugs: attributes.fetch("suggested_category_slugs"),
        suggested_tag_slugs: attributes.fetch("suggested_tag_slugs"),
        search_keywords: attributes.fetch("search_keywords"),
        ai_provider: attributes.fetch("ai_provider"),
        ai_model: attributes.fetch("ai_model"),
        prompt_version: attributes.fetch("prompt_version"),
        summary_basis: attributes.fetch("summary_basis"),
        summary_input_sha256: attributes.fetch("summary_input_sha256"),
        summary_generated_at: parse_time(attributes["summary_generated_at"]),
        taxonomy_status: attributes.fetch("taxonomy_status"),
        taxonomy_origin: attributes.fetch("taxonomy_origin"),
        taxonomy_provider: attributes["taxonomy_provider"],
        taxonomy_model: attributes["taxonomy_model"],
        taxonomy_prompt_version: attributes["taxonomy_prompt_version"],
        taxonomy_input_sha256: attributes["taxonomy_input_sha256"],
        taxonomy_generated_at: parse_time(attributes["taxonomy_generated_at"]),
        taxonomy_confidence: attributes["taxonomy_confidence"],
        summary_status: :succeeded,
        review_status: :review_pending
      )
    end

    def normalize_v1_record(record)
      validate_record_shape!(record, V1_REVISION_KEYS)
      revision = record.fetch("revision").dup
      category_slug = normalize_identifier(revision["suggested_category_slug"])
      raw_tag_slugs = revision.fetch("suggested_tag_slugs")
      tag_slugs = raw_tag_slugs.map do |value|
        resolve_current_tag(value)
      end

      category_slugs = fixed_category_slugs.include?(category_slug) ? [ category_slug ] : []
      validate_resource_enums!(record)
      taxonomy_ready = category_slugs.any? &&
        tag_slugs.all? &&
        (2..6).cover?(tag_slugs.size) &&
        tag_slugs.uniq.size == tag_slugs.size
      revision.merge!(
        "suggested_category_slug" => revision["suggested_category_slug"],
        "suggested_category_slugs" => taxonomy_ready ? category_slugs : [],
        "suggested_tag_slugs" => taxonomy_ready ? tag_slugs : [],
        "search_keywords" => [],
        "taxonomy_status" => taxonomy_ready ? "succeeded" : "queued",
        "taxonomy_origin" => "source",
        "taxonomy_provider" => nil,
        "taxonomy_model" => nil,
        "taxonomy_prompt_version" => nil,
        "taxonomy_input_sha256" => nil,
        "taxonomy_generated_at" => nil,
        "taxonomy_confidence" => nil
      )
      record.merge("revision" => revision)
    end

    def normalize_v2_record(record, taxonomy)
      validate_record_shape!(record, V2_REVISION_KEYS)
      revision = record.fetch("revision").dup
      category_slugs = Array(revision.fetch("suggested_category_slugs")).map { |value| normalize_identifier(value) }
      tag_slugs = Array(revision.fetch("suggested_tag_slugs")).map { |value| resolve_declared_tag!(value, taxonomy) }
      search_keywords = Array(revision.fetch("search_keywords")).map { |value| Search::Normalize.call(value) }.reject(&:blank?)

      validate_resource_enums!(record)
      validate_revision_enums!(revision)
      raise InvalidSnapshot, "Taxonomy status must be succeeded" unless revision.fetch("taxonomy_status") == "succeeded"
      validate_assignment_counts!(category_slugs, tag_slugs)
      reject_duplicates!(category_slugs, "category")
      reject_duplicates!(tag_slugs, "tag")
      reject_duplicates!(search_keywords, "search keyword")
      validate_content_type_tags!(record.fetch("resource").fetch("kind"), tag_slugs)
      category_slugs.each do |slug|
        raise InvalidSnapshot, "Revision category is not declared: #{slug}" unless fixed_category_slugs.include?(slug)
      end
      search_keywords.each do |keyword|
        raise InvalidSnapshot, "Search keyword too long: #{keyword}" if keyword.length > 80
      end

      revision.merge!(
        "suggested_category_slug" => revision["suggested_category_slug"],
        "suggested_category_slugs" => category_slugs,
        "suggested_tag_slugs" => tag_slugs,
        "search_keywords" => search_keywords,
        "taxonomy_status" => revision.fetch("taxonomy_status"),
        "taxonomy_origin" => revision.fetch("taxonomy_origin")
      )
      record.merge("revision" => revision)
    end

    def validate_record_shape!(record, revision_keys)
      raise InvalidSnapshot, "Snapshot record must be an object" unless record.is_a?(Hash)

      resource = record.fetch("resource") { raise InvalidSnapshot, "missing record key: resource" }
      revision = record.fetch("revision") { raise InvalidSnapshot, "missing record key: revision" }
      raise InvalidSnapshot, "Snapshot resource must be an object" unless resource.is_a?(Hash)
      raise InvalidSnapshot, "Snapshot revision must be an object" unless revision.is_a?(Hash)

      RESOURCE_KEYS.each { |key| fetch_required!(resource, key, "resource") }
      revision_keys.each { |key| fetch_required!(revision, key, "revision") }
      validate_resource_values!(resource)
      validate_revision_values!(revision)
    end

    def validate_resource_values!(resource)
      %w[kind provider external_uid canonical_url].each do |key|
        raise InvalidSnapshot, "resource #{key} must be present" if resource.fetch(key).blank?
      end
      parse_time(resource["source_published_at"])
      parse_time(resource["source_updated_at"])
      Integer(resource.fetch("popularity_raw"))
    end

    def validate_revision_values!(revision)
      %w[title source_excerpt source_fingerprint ai_summary ai_provider ai_model prompt_version summary_basis summary_input_sha256].each do |key|
        raise InvalidSnapshot, "revision #{key} must be present" if revision.fetch(key).blank?
      end
      %w[capabilities key_points suggested_tag_slugs].each do |key|
        raise InvalidSnapshot, "revision #{key} must be an array" unless revision.fetch(key).is_a?(Array)
      end
      %w[suggested_category_slugs search_keywords].each do |key|
        next unless revision.key?(key)

        raise InvalidSnapshot, "revision #{key} must be an array" unless revision.fetch(key).is_a?(Array)
      end
      parse_time(revision["summary_generated_at"])
      parse_time(revision["taxonomy_generated_at"]) if revision.key?("taxonomy_generated_at")
    end

    def fetch_required!(payload, key, section)
      payload.fetch(key) { raise InvalidSnapshot, "missing #{section} key: #{key}" }
    end

    def sync_vocabulary(taxonomy)
      taxonomy.fetch("categories").each do |category_attributes|
        category = Category.find_or_initialize_by(slug: category_attributes.fetch("slug"))
        category.update!(
          name: category_attributes.fetch("name"),
          position: category_attributes.fetch("position"),
          active: category_attributes.fetch("active")
        )
      end

      declared_tag_slugs = taxonomy.fetch("tags").map { |tag| tag.fetch("slug") }
      Tag.where.not(slug: declared_tag_slugs).update_all(active: false, filterable: false, updated_at: Time.current)
      taxonomy.fetch("tags").each do |tag_attributes|
        tag = Tag.find_or_initialize_by(slug: tag_attributes.fetch("slug"))
        tag.update!(
          name: tag_attributes.fetch("name"),
          normalized_name: tag_attributes.fetch("slug"),
          vocabulary_group: tag_attributes.fetch("group"),
          position: tag_attributes.fetch("position"),
          active: tag_attributes.fetch("active"),
          filterable: tag_attributes.fetch("filterable")
        )
      end

      declared_tag_ids = Tag.where(slug: declared_tag_slugs).select(:id)
      declared_aliases = taxonomy.fetch("tags").flat_map { |tag| tag.fetch("aliases").map { |alias_name| Taxonomy::Registry.normalize(alias_name) } }
      TagAlias.where.not(tag_id: declared_tag_ids).delete_all
      TagAlias.where(normalized_name: declared_aliases).where.not(tag_id: declared_tag_ids).delete_all

      taxonomy.fetch("tags").each do |tag_attributes|
        sync_aliases(Tag.find_by!(slug: tag_attributes.fetch("slug")), tag_attributes.fetch("aliases"))
      end
    end

    def sync_aliases(tag, aliases)
      normalized_aliases = aliases.map { |alias_name| Taxonomy::Registry.normalize(alias_name) }
      tag.tag_aliases.where.not(normalized_name: normalized_aliases).delete_all
      TagAlias.where(normalized_name: normalized_aliases).where.not(tag_id: tag.id).delete_all
      aliases.each do |alias_name|
        normalized_name = Taxonomy::Registry.normalize(alias_name)
        tag.tag_aliases.find_or_initialize_by(normalized_name: normalized_name).update!(name: alias_name)
      end
    end

    def validate_assignment_counts!(category_slugs, tag_slugs)
      raise InvalidSnapshot, "Category count must be 1-3: #{category_slugs.size}" unless (1..3).cover?(category_slugs.size)
      raise InvalidSnapshot, "Tag count must be 2-6: #{tag_slugs.size}" unless (2..6).cover?(tag_slugs.size)
    end

    def validate_content_type_tags!(kind, tag_slugs)
      raise InvalidSnapshot, "Tag restates content type: mcp" if kind == "mcp" && tag_slugs.include?("mcp")
      raise InvalidSnapshot, "Tag restates content type: agent-skills" if kind == "skill" && tag_slugs.include?("agent-skills")
    end

    def resolve_declared_tag!(value, taxonomy)
      normalized = normalize_identifier(value)
      declared_tags = taxonomy.fetch("tags")
      tag_slugs = declared_tags.map { |tag| tag.fetch("slug") }
      return normalized if tag_slugs.include?(normalized)

      alias_map = declared_tags.each_with_object({}) do |tag, mapping|
        tag.fetch("aliases").each do |alias_name|
          mapping[Taxonomy::Registry.normalize(alias_name)] = tag.fetch("slug")
        end
      end
      alias_map.fetch(Taxonomy::Registry.normalize(value)) do
        raise InvalidSnapshot, "Revision tag is not declared: #{normalized}"
      end
    end

    def resolve_current_tag(value)
      normalized = normalize_identifier(value)
      Tag.where(active: true).find_by(slug: normalized)&.slug ||
        TagAlias.joins(:tag).merge(Tag.where(active: true)).find_by(normalized_name: Taxonomy::Registry.normalize(value))&.tag&.slug
    end

    def validate_resource_enums!(record)
      resource = record.fetch("resource")
      raise InvalidSnapshot, "Unknown resource kind: #{resource.fetch('kind')}" unless Resource.kinds.key?(resource.fetch("kind"))
      unless Resource.source_providers.key?(resource.fetch("provider"))
        raise InvalidSnapshot, "Unknown source provider: #{resource.fetch('provider')}"
      end
    end

    def validate_revision_enums!(revision)
      unless ResourceRevision.taxonomy_statuses.key?(revision.fetch("taxonomy_status"))
        raise InvalidSnapshot, "Unknown taxonomy status: #{revision.fetch('taxonomy_status')}"
      end
      unless ResourceRevision.taxonomy_origins.key?(revision.fetch("taxonomy_origin"))
        raise InvalidSnapshot, "Unknown taxonomy origin: #{revision.fetch('taxonomy_origin')}"
      end
    end

    def fixed_category_slugs
      Taxonomy::Registry.definition.fetch("categories").map { |category| category.fetch("slug") }
    end

    def reject_duplicates!(values, label)
      duplicate = values.tally.find { |_value, count| count > 1 }&.first
      raise InvalidSnapshot, "Duplicate #{label}: #{duplicate}" if duplicate
    end

    def normalize_identifier(value)
      Taxonomy::Registry.normalize(value.to_s.unicode_normalize(:nfkc).strip)
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
