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
    attr_reader :readme_calls, :queries

    def initialize(results)
      @results = results
      @readme_calls = []
      @queries = []
    end

    def search_repositories(query:, limit:, page: 1)
      queries << query
      raise "page missing" unless page.positive?
      @results.fetch(query).first(limit)
    end

    def readme(full_name:)
      readme_calls << full_name
      "README for #{full_name}"
    end
  end

  test "maps a GitHub repository and README excerpt to an MCP snapshot" do
    repositories = [ {
      "id" => 42,
      "name" => "issue-mcp",
      "full_name" => "example/issue-mcp",
      "html_url" => "https://github.com/example/issue-mcp",
      "description" => "Search GitHub issues",
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
    shared = repository("shared/skill", stars: 300)
    first_only = repository("first/skill", stars: 200)
    second_only = repository("second/skill", stars: 100)
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
    assert_equal [ "shared/skill" ], client.readme_calls
    assert_includes snapshots.second.excerpt, "Repository description"
    assert_includes snapshots.second.excerpt, "Ruby"
  end

  test "keeps MCP server repositories and rejects adjacent MCP clients and SDKs" do
    catalog = Sources::GithubCatalog.new(kind: :mcp, client: FakeClient.new([], nil))

    assert catalog.send(:relevant_repository?, repository("github/github-mcp-server", stars: 100))
    assert catalog.send(:relevant_repository?, repository("modelcontextprotocol/servers", stars: 90))
    refute catalog.send(:relevant_repository?, repository("n8n-io/n8n", stars: 80))
    refute catalog.send(:relevant_repository?, repository("google-gemini/gemini-cli", stars: 70))
    refute catalog.send(:relevant_repository?, repository("modelcontextprotocol/python-sdk", stars: 60))
  end

  test "requires an explicit skill signal for skill repositories" do
    catalog = Sources::GithubCatalog.new(kind: :skill, client: FakeClient.new([], nil))
    skill = repository("example/humanizer", stars: 100).merge("description" => "A Claude Code skill")

    assert catalog.send(:relevant_repository?, skill)
    refute catalog.send(:relevant_repository?, repository("example/reactive-resume", stars: 90))
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
