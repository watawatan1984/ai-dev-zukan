module Sources
  Snapshot = Data.define(
    :kind,
    :provider,
    :external_uid,
    :canonical_url,
    :title,
    :author_name,
    :excerpt,
    :source_fingerprint,
    :source_published_at,
    :source_updated_at,
    :popularity_raw
  ) do
    def initialize(**attributes)
      super
      validate!
    end

    def normalized_canonical_url
      Sources::CanonicalUrl.normalize(canonical_url)
    end

    private

    def validate!
      required = %i[kind provider external_uid canonical_url title source_fingerprint]
      missing = required.select { |attribute| public_send(attribute).blank? }
      raise ArgumentError, "Missing snapshot attributes: #{missing.join(', ')}" if missing.any?
    end
  end
end
