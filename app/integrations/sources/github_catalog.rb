module Sources
  class GithubCatalog
    QUERIES = {
      mcp: '"model context protocol" in:name,description,readme',
      skill: '"agent skill" in:name,description,readme'
    }.freeze

    def initialize(kind:, client: GithubClient.new)
      @kind = kind.to_sym
      @client = client
      raise ArgumentError, "Unsupported GitHub catalog kind" unless QUERIES.key?(@kind)
    end

    def fetch(limit:)
      client.search_repositories(query: QUERIES.fetch(kind), limit:).map do |repository|
        build_snapshot(repository)
      end
    end

    private

    attr_reader :kind, :client

    def build_snapshot(repository)
      full_name = repository.fetch("full_name")
      excerpt = client.readme(full_name:) || repository["description"]
      Sources::Snapshot.new(
        kind: kind,
        provider: :github,
        external_uid: full_name,
        canonical_url: repository.fetch("html_url"),
        title: repository.fetch("name"),
        author_name: repository.dig("owner", "login"),
        excerpt: excerpt.to_s.truncate(4_000),
        source_fingerprint: fingerprint(repository, excerpt),
        source_published_at: parse_time(repository["created_at"]),
        source_updated_at: parse_time(repository["pushed_at"]),
        popularity_raw: repository["stargazers_count"].to_i
      )
    end

    def fingerprint(repository, excerpt)
      Digest::SHA256.hexdigest([
        repository["id"], repository["pushed_at"], excerpt
      ].join("\u0000"))
    end

    def parse_time(value)
      Time.iso8601(value) if value.present?
    end
  end
end
