require "test_helper"

class AdminResourceWorkflowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "admin manually creates a review candidate" do
    sign_in users(:admin)

    assert_difference [ "Resource.count", "ResourceRevision.count" ], 1 do
      post admin_resources_path, params: {
        resource: {
          kind: "mcp",
          title: "Manual MCP",
          canonical_url: "https://github.com/example/manual-mcp/",
          author_name: "example",
          source_excerpt: "Manually registered source",
          ai_summary: "開発環境を操作するためのMCPサーバーです。"
        }
      }
    end

    revision = ResourceRevision.order(:id).last
    assert_redirected_to admin_resource_revision_path(revision)
    assert_predicate revision, :review_pending?
    assert_predicate revision, :summary_status_manually_written?
    assert_predicate revision.resource, :unpublished?
    assert_equal "https://github.com/example/manual-mcp", revision.resource.normalized_canonical_url
  end

  test "admin can send a manual candidate through the AI review queue" do
    sign_in users(:admin)

    assert_enqueued_jobs 1, only: SummarizeRevisionJob do
      post admin_resources_path, params: {
        resource: {
          kind: "skill",
          title: "Manual Skill",
          canonical_url: "https://github.com/example/manual-skill",
          source_excerpt: "SkillのREADME抜粋です。",
          ai_summary: ""
        }
      }
    end

    revision = ResourceRevision.order(:id).last
    assert_predicate revision, :summary_status_queued?
    assert_predicate revision, :draft?
  end
end
