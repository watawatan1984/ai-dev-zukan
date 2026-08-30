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
    SEARCH_PAGES = 5
    MCP_EXCLUDED_NAME = /(sdk|client|agent|framework|library|proxy|router|adapter|bridge|beginner|awesome|registry|specification|tutorial|course|guide|examples?)/i
    MCP_NAME = /(^|[-_.])mcp($|[-_.])/i
    MCP_SERVER_SIGNAL = /\bmcp[- ]?servers?\b|model context protocol.{0,40}\bservers?\b|\bservers?\b.{0,40}model context protocol/i
    MCP_SERVER_TOPIC = /\A(?:mcp-server|model-context-protocol-server)\z/i
    MCP_EXCLUDED_CONTEXT = /\b(framework|sdk|client library|tool development library|server management app|registry metadata)\b|expose .{0,60} endpoints as .{0,60}mcp.{0,20}tools/i
    SKILL_COLLECTION_NAME_SIGNAL = /(^|[-_.])skills($|[-_.])/i
    SKILL_DESCRIPTION_SIGNAL = /\b(?:agent|agentic|claude(?: code)?|codex|copilot)[ -]skills?\b|\bskills? for (?:ai )?(?:coding )?agents?\b|SKILL\.md/i
    SKILL_TOOL_NAME = /(^|[-_.])(skill(?:opt|spector|kit)?|skills?)[-_.]?(builder|scanner|recorder|optimizer|creator|generator|manager|marketplace|registry)($|[-_.])/i
    SKILL_DIRECTORY_NAME = /(^|[-_.])(awesome|directory|directories|catalog|list)([-_.]|$)/i
    SKILL_WEAK_PRODUCT_SIGNAL = /\b(builder|scanner|optimizer|recorder|workbench|platform|framework|editor|web application|command[- ]line tool|cli|skill layer)\b/i
    SKILL_NON_CONTENT_SIGNAL = /specification and documentation|(?:desktop app|tool|cli).{0,50}\b(?:manage|install|package|sync)\b.{0,30}\bskills?\b|\bpackage[- ]manager\b.{0,20}\b(?:project|tool|cli|application)\b.{0,50}\bskills?\b|\bskills?\b.{0,50}\bpackage[- ]manager\b.{0,20}\b(?:project|tool|cli|application)\b|\b(?:skill installer|package manager for .{0,30}agents?|test runner for .{0,30}skills?|evaluation .{0,20}tool for .{0,30}skills?)\b|(?:curated|awesome) list of|tutorials?.{0,30}guides?.{0,30}(?:directory|directories)|\b(?:directory|directories) of .{0,30}skills?\b/i

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

      return true if repository.fetch("full_name") == "modelcontextprotocol/servers"

      context = repository_context_text(repository)
      return false if context.match?(MCP_EXCLUDED_CONTEXT)

      server_topic = Array(repository["topics"]).any? { |topic| topic.match?(MCP_SERVER_TOPIC) }
      name.match?(MCP_NAME) && (context.match?(MCP_SERVER_SIGNAL) || server_topic)
    end

    def skill_repository?(repository)
      name = repository.fetch("name")
      description = repository["description"].to_s
      return false if name.match?(SKILL_TOOL_NAME)
      return false if name.match?(SKILL_DIRECTORY_NAME)
      return false if description.match?(SKILL_NON_CONTENT_SIGNAL)

      collection_name = name.match?(SKILL_COLLECTION_NAME_SIGNAL)
      explicit_description = description.first(160).match?(SKILL_DESCRIPTION_SIGNAL)
      return false unless collection_name || explicit_description
      return false if !collection_name && description.match?(SKILL_WEAK_PRODUCT_SIGNAL)

      true
    end

    def repository_context_text(repository)
      [ repository["name"], repository["description"] ]
        .compact
        .join(" ")
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
