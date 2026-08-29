module Sources
  class QiitaCatalog
    EXCERPT_LIMIT = 2_000

    def initialize(client: QiitaClient.new)
      @client = client
    end

    def fetch(limit:)
      client.items(limit:).map { |item| build_snapshot(item) }
    end

    private

    attr_reader :client

    def build_snapshot(item)
      excerpt = item["body"].to_s.truncate(EXCERPT_LIMIT)
      Sources::Snapshot.new(
        kind: :qiita_article,
        provider: :qiita,
        external_uid: item.fetch("id"),
        canonical_url: item.fetch("url"),
        title: item.fetch("title"),
        author_name: item.dig("user", "id"),
        excerpt: excerpt,
        source_fingerprint: Digest::SHA256.hexdigest([ item["id"], item["updated_at"], excerpt ].join("\u0000")),
        source_published_at: parse_time(item["created_at"]),
        source_updated_at: parse_time(item["updated_at"]),
        popularity_raw: item["likes_count"].to_i
      )
    end

    def parse_time(value)
      Time.iso8601(value) if value.present?
    end
  end
end
