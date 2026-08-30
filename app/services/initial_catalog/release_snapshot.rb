module InitialCatalog
  class ReleaseSnapshot
    ConfirmationRequired = Class.new(StandardError)
    ReviewerNotAuthorized = Class.new(StandardError)
    InvalidRelease = Class.new(StandardError)

    CONFIRMATION = "release-existing-catalog-snapshot"

    Result = Data.define(:target, :switched_count, :current_counts) do
      def complete?
        current_counts == InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { target }.transform_keys(&:to_s)
      end
    end

    def self.call(path:, target: Bootstrap::MAX_LIMIT, reviewer:, confirmation:)
      new(path:, target:, reviewer:, confirmation:).call
    end

    def initialize(path:, target:, reviewer:, confirmation:)
      @path = Pathname(path)
      @target = target.to_i.clamp(1, Bootstrap::MAX_LIMIT)
      @reviewer = reviewer
      @confirmation = confirmation
    end

    def call
      raise ConfirmationRequired, "Set INITIAL_CATALOG_SNAPSHOT_RELEASE=#{CONFIRMATION} to update the existing catalog" unless confirmation == CONFIRMATION
      raise ReviewerNotAuthorized, "Only the locked system release reviewer can update the existing catalog" unless locked_system_reviewer?

      records = snapshot_records
      Resource.transaction do
        import_snapshot!
        candidates = release_candidates(records)
        validate_release!(candidates)
        switched_count = switch_current_revisions(candidates)
        result = Result.new(target:, switched_count:, current_counts:)
        raise InvalidRelease, "Existing catalog snapshot release is incomplete" unless result.complete?

        result
      end
    end

    private

    attr_reader :path, :target, :reviewer, :confirmation

    def snapshot_records
      payload = JSON.parse(path.read)
      expected_counts = InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { target }.transform_keys(&:to_s)
      raise InvalidRelease, "Snapshot target does not match" unless payload["target"] == target
      raise InvalidRelease, "Snapshot counts do not match" unless payload["counts"] == expected_counts

      records = payload.fetch("records")
      checksum = Digest::SHA256.hexdigest(JSON.generate(records))
      raise InvalidRelease, "Snapshot checksum does not match" unless checksum == payload["records_sha256"]

      records
    rescue ArgumentError, KeyError, JSON::ParserError => error
      raise InvalidRelease, error.message
    end

    def import_snapshot!
      InitialCatalog::ImportSnapshot.call(path:, target:)
    rescue InitialCatalog::ImportSnapshot::InvalidSnapshot => error
      raise InvalidRelease, error.message
    end

    def release_candidates(records)
      records.map do |record|
        resource_data = record.fetch("resource")
        revision_data = record.fetch("revision")
        resource = find_existing_resource!(resource_data)
        revision = resource.revisions.where(source_fingerprint: revision_data.fetch("source_fingerprint")).sole
        [ resource, revision ]
      rescue ActiveRecord::RecordNotFound, ActiveRecord::SoleRecordExceeded => error
        raise InvalidRelease, error.message
      end
    end

    def validate_release!(candidates)
      validate_kind_counts!(candidates)
      candidates.each do |resource, revision|
        raise InvalidRelease, "Resource #{resource.id} must already be published" unless resource.published?
        raise InvalidRelease, "Resource #{resource.id} must have an approved current revision" unless resource.current_revision&.approved?
        raise InvalidRelease, "Revision #{revision.id} must belong to a published resource" unless revision.resource_id == resource.id
        raise InvalidRelease, "Revision #{revision.id} taxonomy must be succeeded" unless revision.taxonomy_status_succeeded?
        raise InvalidRelease, "Revision #{revision.id} must be review pending or already current" unless publishable_or_current?(resource, revision)

        validation = Taxonomy::ValidateSuggestion.call(revision:)
        raise InvalidRelease, "Revision #{revision.id} taxonomy invalid: #{validation.errors.join(', ')}" unless validation.valid?
      end
    end

    def validate_kind_counts!(candidates)
      counts = candidates.map { |resource, _revision| resource.kind }.tally
      expected_counts = InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { target }.transform_keys(&:to_s)
      raise InvalidRelease, "Release candidates must contain exactly #{target} resources for every kind" unless counts == expected_counts

      resource_ids = candidates.map { |resource, _revision| resource.id }
      duplicate_id = resource_ids.tally.find { |_id, count| count > 1 }&.first
      raise InvalidRelease, "Duplicate snapshot resource: #{duplicate_id}" if duplicate_id
    end

    def switch_current_revisions(candidates)
      candidates.count do |resource, revision|
        next false if resource.current_revision_id == revision.id

        Editorial::ApproveAndPublish.call(
          revision:,
          reviewer:,
          request_id: "existing-catalog-snapshot-release"
        )
        true
      end
    end

    def find_existing_resource!(resource_data)
      resource = Resource.find_by!(
        kind: resource_data.fetch("kind"),
        source_provider: resource_data.fetch("provider"),
        external_uid: resource_data.fetch("external_uid")
      )
      normalized_url = Sources::CanonicalUrl.normalize(resource_data.fetch("canonical_url"))
      raise InvalidRelease, "Resource #{resource.id} canonical URL does not match snapshot" unless resource.normalized_canonical_url == normalized_url

      resource
    end

    def publishable_or_current?(resource, revision)
      (revision.review_pending? && revision.ai_summary.present?) ||
        (revision.approved? && resource.current_revision_id == revision.id)
    end

    def current_counts
      InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with do |kind|
        Resource.where(kind: kind).publicly_visible.count
      end.transform_keys(&:to_s)
    end

    def locked_system_reviewer?
      reviewer&.admin? &&
        reviewer.email == InitialCatalog::ReleaseReviewer::DEFAULT_EMAIL &&
        reviewer.access_locked? &&
        reviewer.email.end_with?(".invalid")
    end
  end
end
