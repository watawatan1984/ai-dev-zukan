module Ingestion
  class UpsertSnapshot
    Result = Data.define(:status, :resource, :revision)

    def self.call(snapshot:)
      new(snapshot: snapshot).call
    end

    def initialize(snapshot:)
      @snapshot = snapshot
    end

    def call
      Resource.transaction do
        resource = find_or_build_resource
        update_source_metadata(resource)

        existing_revision = resource.revisions.find_by(
          source_fingerprint: snapshot.source_fingerprint
        )
        return Result.new(status: :unchanged, resource: resource, revision: existing_revision) if existing_revision

        revision = resource.revisions.create!(
          origin: :imported,
          title: snapshot.title,
          author_name: snapshot.author_name,
          source_excerpt: snapshot.excerpt,
          source_fingerprint: snapshot.source_fingerprint,
          summary_status: :queued,
          review_status: :draft
        )

        Result.new(status: :created_revision, resource: resource, revision: revision)
      end
    end

    private

    attr_reader :snapshot

    def find_or_build_resource
      identity = Resource.find_by(
        kind: snapshot.kind,
        source_provider: snapshot.provider,
        external_uid: snapshot.external_uid
      )
      canonical_match = Resource.find_by(
        kind: snapshot.kind,
        normalized_canonical_url: snapshot.normalized_canonical_url
      )

      (identity || canonical_match || Resource.new(kind: snapshot.kind)).tap do |resource|
        resource.slug ||= available_slug
        resource.source_provider = snapshot.provider
        resource.external_uid = snapshot.external_uid
      end
    end

    def update_source_metadata(resource)
      resource.update!(
        canonical_url: snapshot.canonical_url,
        normalized_canonical_url: snapshot.normalized_canonical_url,
        source_published_at: snapshot.source_published_at,
        source_updated_at: snapshot.source_updated_at,
        popularity_raw: snapshot.popularity_raw || 0,
        popularity_score: Popularity::Normalize.call(
          provider: snapshot.provider,
          raw_value: snapshot.popularity_raw
        ),
        last_synced_at: Time.current
      )
    end

    def available_slug
      base = snapshot.title.parameterize.presence || snapshot.kind.to_s
      return base unless Resource.exists?(slug: base)

      digest = Digest::SHA256.hexdigest("#{snapshot.provider}:#{snapshot.external_uid}").first(8)
      "#{base}-#{digest}"
    end
  end
end
