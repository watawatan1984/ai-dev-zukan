module Sources
  class GithubCatalog
    QUERIES = {
      mcp: [
        "topic:mcp-server stars:>=1 archived:false fork:false",
        '"model context protocol" in:name,description stars:>=2 archived:false fork:false'
      ],
      skill: [
        "topic:agent-skills stars:>=1 archived:false fork:false",
        "topic:claude-skills stars:>=1 archived:false fork:false"
      ]
    }.freeze
    SEARCH_PAGES = 2
    MCP_EXCLUDED_NAME = /(sdk|beginner|awesome|registry|specification|tutorial|course|guide|examples?)/i
    MCP_NAME = /(^|[-_.])mcp($|[-_.])/i
    SKILL_SIGNAL = /(^|[^a-z])skills?([^a-z]|$)|SKILL\.md/i

    def initialize(
      kind:,
      client: GithubClient.new,
      readme_limit: ENV.fetch("GITHUB_README_FETCH_LIMIT", 10).to_i
    )
      @kind = kind.to_sym
      @client = client
      @readme_limit = readme_limit.to_i.clamp(0, 100)
      raise ArgumentError, "Unsupported GitHub catalog kind" unless QUERIES.key?(@kind)
    end

    def fetch(limit:)
      repositories = {}
      QUERIES.fetch(kind).each do |query|
        break if repositories.length >= limit

        1.upto(SEARCH_PAGES) do |page|
          client.search_repositories(query:, limit: [ limit, 100 ].min, page:).each do |repository|
            next unless relevant_repository?(repository)

            repositories[repository.fetch("full_name")] ||= repository
          end
          break if repositories.length >= limit
        end
      end

      repositories.values
        .sort_by { |repository| [ -repository["stargazers_count"].to_i, repository.fetch("full_name") ] }
        .first(limit)
        .map.with_index do |repository, index|
          build_snapshot(repository, fetch_readme: index < readme_limit)
      end
    end

    private

    attr_reader :kind, :client, :readme_limit

    def relevant_repository?(repository)
      return skill_repository?(repository) if kind == :skill

      name = repository.fetch("name")
      return false if name.match?(MCP_EXCLUDED_NAME)

      name.match?(MCP_NAME) || repository.fetch("full_name") == "modelcontextprotocol/servers"
    end

    def skill_repository?(repository)
      [ repository["name"], repository["description"] ].compact.join(" ").match?(SKILL_SIGNAL)
    end

    def build_snapshot(repository, fetch_readme:)
      full_name = repository.fetch("full_name")
      excerpt = fetch_readme ? client.readme(full_name:) : nil
      excerpt = repository_context(repository) if excerpt.blank?
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

    def repository_context(repository)
      [
        repository["description"],
        ("Primary language: #{repository['language']}" if repository["language"].present?),
        ("GitHub topics: #{Array(repository['topics']).join(', ')}" if repository["topics"].present?)
      ].compact.join("\n").presence || repository.fetch("name")
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
