require "test_helper"

class Sources::GithubCatalogTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:repositories, :readme_text) do
    def search_repositories(query:, limit:, page: 1)
      raise "query missing" if query.blank?
      raise "page missing" unless page.positive?

      repositories.first(limit)
    end

    def readme(full_name:)
      raise "wrong repository" unless full_name == repositories.first.fetch("full_name")

      readme_text
    end
  end


  class MultiQueryClient
    def initialize(results)
      @results = results
    end

    def search_repositories(query:, limit:, page: 1)
      raise "page missing" unless page.positive?
      @results.fetch(query).first(limit)
    end

    def readme(full_name:)
      "README for #{full_name}"
    end
  end

  test "maps a GitHub repository and README excerpt to an MCP snapshot" do
    repositories = [ {
      "id" => 42,
      "name" => "issue-mcp",
      "full_name" => "example/issue-mcp",
      "html_url" => "https://github.com/example/issue-mcp",
      "description" => "MCP server for searching GitHub issues",
      "owner" => { "login" => "example" },
      "created_at" => "2026-01-02T03:04:05Z",
      "pushed_at" => "2026-08-20T11:12:13Z",
      "stargazers_count" => 321
    } ]
    catalog = Sources::GithubCatalog.new(
      kind: :mcp,
      client: FakeClient.new(repositories, "README body")
    )

    snapshot = catalog.fetch(limit: 10).sole

    assert_equal :mcp, snapshot.kind
    assert_equal :github, snapshot.provider
    assert_equal "example/issue-mcp", snapshot.external_uid
    assert_equal "README body", snapshot.excerpt
    assert_equal 321, snapshot.popularity_raw
    assert_equal Time.iso8601("2026-08-20T11:12:13Z"), snapshot.source_updated_at
  end

  test "star count changes do not create a new content revision" do
    repository = {
      "id" => 42,
      "name" => "issue-mcp",
      "full_name" => "example/issue-mcp",
      "html_url" => "https://github.com/example/issue-mcp",
      "description" => "MCP server for searching GitHub issues",
      "owner" => { "login" => "example" },
      "pushed_at" => "2026-08-20T11:12:13Z",
      "stargazers_count" => 321
    }
    first = Sources::GithubCatalog.new(
      kind: :mcp,
      client: FakeClient.new([ repository ], "same README")
    ).fetch(limit: 1).sole
    repository["stargazers_count"] = 322
    second = Sources::GithubCatalog.new(
      kind: :mcp,
      client: FakeClient.new([ repository ], "same README")
    ).fetch(limit: 1).sole

    assert_equal first.source_fingerprint, second.source_fingerprint
    refute_equal first.popularity_raw, second.popularity_raw
  end

  test "merges configured searches, removes duplicates, and limits README requests" do
    first_query, second_query = Sources::GithubCatalog::QUERIES.fetch(:skill)
    shared = repository("shared/skill", stars: 300).merge("description" => "Agent Skills for coding agents")
    first_only = repository("first/skill", stars: 200).merge("description" => "Agent Skills for coding agents")
    second_only = repository("second/skill", stars: 100).merge("description" => "Agent Skills for coding agents")
    client = MultiQueryClient.new(
      first_query => [ shared, first_only ],
      second_query => [ shared, second_only ]
    )
    catalog = Sources::GithubCatalog.new(
      kind: :skill,
      client: client,
      readme_limit: 1
    )

    snapshots = catalog.fetch(limit: 3)

    assert_equal 3, snapshots.length
    assert_equal [ "shared/skill", "first/skill", "second/skill" ], snapshots.map(&:external_uid)
    assert_equal "README for shared/skill", snapshots.first.excerpt
    assert_includes snapshots.second.excerpt, "Agent Skills for coding agents"
    assert_includes snapshots.second.excerpt, "Ruby"
  end

  test "keeps MCP server repositories and rejects adjacent MCP clients and SDKs" do
    first_query, second_query = Sources::GithubCatalog::QUERIES.fetch(:mcp)
    server = repository("github/github-mcp-server", stars: 100).merge(
      "description" => "Official Model Context Protocol server for GitHub"
    )
    official = repository("modelcontextprotocol/servers", stars: 90)
    client = MultiQueryClient.new(
      first_query => [
        server,
        official,
        repository("modelcontextprotocol/mcp-client", stars: 80),
        repository("tadata-org/fastapi_mcp", stars: 75).merge(
          "description" => "Expose your FastAPI endpoints as Model Context Protocol (MCP) tools"
        )
      ],
      second_query => [
        repository("modelcontextprotocol/python-sdk", stars: 70),
        repository("mark3labs/mcp-go", stars: 60).merge(
          "description" => "A Go implementation of the Model Context Protocol"
        ),
        repository("lastmile-ai/mcp-agent", stars: 50).merge(
          "description" => "Build agents using Model Context Protocol"
        )
      ]
    )

    snapshots = Sources::GithubCatalog.new(kind: :mcp, client:, readme_limit: 0).fetch(limit: 10)

    assert_equal [ "github/github-mcp-server", "modelcontextprotocol/servers" ], snapshots.map(&:external_uid)
  end

  test "requires an explicit skill signal for skill repositories" do
    first_query, second_query = Sources::GithubCatalog::QUERIES.fetch(:skill)
    skill = repository("example/humanizer", stars: 100).merge("description" => "A Claude Code skill")
    package_manager_audit = repository("example/npm-security", stars: 95).merge(
      "description" => "Claude Code skill for npm package manager security audits"
    )
    collection = repository("example/agent-skills", stars: 90)
    client = MultiQueryClient.new(
      first_query => [ skill, package_manager_audit, collection, repository("googleworkspace/cli", stars: 80).merge(
        "description" => "A command-line tool with Agent Skills"
      ), repository("example/skills-hub", stars: 70).merge(
        "description" => "A desktop app to manage and sync Agent Skills"
      ), repository("example/awesome-agent-skills", stars: 65).merge(
        "description" => "A curated list of awesome Agent Skills and directories"
      ) ],
      second_query => [
        repository("example/reactive-resume", stars: 60),
        repository("agentskills/agentskills", stars: 50).merge(
          "description" => "Specification and documentation for Agent Skills"
        ),
        repository("example/ai-agent-skills", stars: 40).merge(
          "description" => "Universal skill installer and package manager for AI coding agents"
        ),
        repository("example/agent-skill-package-manager", stars: 35).merge(
          "description" => "Educational package-manager project for AI agent skills. Not actively maintained."
        ),
        repository("example/agent-skills-eval", stars: 30).merge(
          "description" => "A test runner for agentskills.io-style AI agent skills"
        ),
        repository("example/awesome-nlp-resources", stars: 20).merge(
          "description" => "A curated list of resources for NLP. Includes Claude Code skills to search resources."
        ),
        repository("example/hot-monitor", stars: 10).merge(
          "description" => "AI monitoring web application with crawling, email and dashboards that also packages its monitoring feature as Agent Skills"
        ),
        repository("example/human-skill-tree", stars: 5).merge(
          "description" => "AI-Powered Skill Tree for Lifelong Human Learning"
        )
      ]
    )

    snapshots = Sources::GithubCatalog.new(kind: :skill, client:, readme_limit: 0).fetch(limit: 10)

    assert_equal [ "example/humanizer", "example/npm-security", "example/agent-skills" ], snapshots.map(&:external_uid)
  end

  private

  def repository(full_name, stars:)
    owner, name = full_name.split("/", 2)
    {
      "id" => full_name.hash.abs,
      "name" => name,
      "full_name" => full_name,
      "html_url" => "https://github.com/#{full_name}",
      "description" => "Repository description",
      "owner" => { "login" => owner },
      "created_at" => "2026-01-02T03:04:05Z",
      "pushed_at" => "2026-08-20T11:12:13Z",
      "stargazers_count" => stars,
      "language" => "Ruby",
      "topics" => [ "agent-skill" ]
    }
  end
end
