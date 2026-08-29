require "test_helper"

class UserLibraryTest < ActionDispatch::IntegrationTest
  test "signed in user bookmarks a published resource" do
    user = users(:regular)
    resource = Resource.create!(
      kind: :mcp,
      slug: "bookmarkable-mcp",
      canonical_url: "https://github.com/example/bookmarkable-mcp",
      normalized_canonical_url: "https://github.com/example/bookmarkable-mcp",
      source_provider: :github,
      external_uid: "example/bookmarkable-mcp"
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Bookmarkable MCP",
      ai_summary: "ブックマーク操作を確認するMCPです。",
      source_fingerprint: "bookmarkable-v1",
      summary_status: :succeeded,
      review_status: :approved
    )
    resource.publish!(revision: revision)
    sign_in user

    assert_difference "user.bookmarks.count", 1 do
      post resource_bookmark_path(resource.slug), headers: { "HTTP_REFERER" => resources_url }
    end

    assert_redirected_to resources_url
  end
end
