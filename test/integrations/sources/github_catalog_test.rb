require "test_helper"

class Sources::GithubCatalogTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:repositories, :readme_text) do
    def search_repositories(query:, limit:)
      raise "query missing" if query.blank?

      repositories.first(limit)
    end

    def readme(full_name:)
      raise "wrong repository" unless full_name == repositories.first.fetch("full_name")

      readme_text
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
end
