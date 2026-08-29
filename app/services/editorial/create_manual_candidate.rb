module Editorial
  class CreateManualCandidate
    class ActorNotAuthorized < StandardError; end

    def self.call(attributes:, actor:, request_id: nil)
      new(attributes: attributes, actor: actor, request_id: request_id).call
    end

    def initialize(attributes:, actor:, request_id: nil)
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
      @request_id = request_id
    end

    def call
      raise ActorNotAuthorized, "Only an admin can create manual candidates" unless actor.admin?

      Resource.transaction do
        resource = find_or_build_resource
        resource.save!
        revision = resource.revisions.find_or_create_by!(source_fingerprint: source_fingerprint) do |candidate|
          candidate.assign_attributes(revision_attributes)
        end
        AdminAuditLog.create!(
          actor: actor,
          auditable: revision,
          action: "resource_revision.create_manual_candidate",
          request_id: request_id,
          changeset: { resource_id: resource.id, title: revision.title }
        )
        revision
      end
    end

    private

    attr_reader :attributes, :actor, :request_id

    def find_or_build_resource
      normalized_url = Sources::CanonicalUrl.normalize(attributes.fetch(:canonical_url))
      Resource.find_or_initialize_by(
        kind: attributes.fetch(:kind),
        normalized_canonical_url: normalized_url
      ).tap do |resource|
        resource.slug ||= available_slug
        resource.canonical_url = attributes.fetch(:canonical_url)
        resource.source_provider ||= :manual
      end
    end

    def revision_attributes
      summary_present = attributes[:ai_summary].present?
      {
        origin: :manual,
        title: attributes.fetch(:title),
        author_name: attributes[:author_name],
        source_excerpt: attributes[:source_excerpt],
        ai_summary: attributes[:ai_summary],
        summary_status: summary_present ? :manually_written : :queued,
        review_status: summary_present ? :review_pending : :draft
      }
    end

    def source_fingerprint
      Digest::SHA256.hexdigest(
        attributes.slice(:title, :author_name, :source_excerpt, :ai_summary).to_json
      )
    end

    def available_slug
      base = attributes.fetch(:title).parameterize.presence || attributes.fetch(:kind).to_s
      return base unless Resource.exists?(slug: base)

      "#{base}-#{source_fingerprint.first(8)}"
    end
  end
end
