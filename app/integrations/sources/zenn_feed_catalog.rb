module Sources
  class ZennFeedCatalog
    def initialize(client: ZennFeedClient.new)
      @client = client
    end

    def fetch(limit:)
      client.entries(limit:).map { |entry| build_snapshot(entry) }
    end

    private

    attr_reader :client

    def build_snapshot(entry)
      Sources::Snapshot.new(
        kind: :zenn_article,
        provider: :zenn,
        external_uid: entry.id,
        canonical_url: entry.url,
        title: entry.title,
        author_name: entry.author,
        excerpt: entry.summary.to_s.truncate(2_000),
        source_fingerprint: Digest::SHA256.hexdigest([ entry.id, entry.updated_at, entry.summary ].join("\u0000")),
        source_published_at: entry.published_at,
        source_updated_at: entry.updated_at,
        popularity_raw: 0
      )
    end
  end
end
