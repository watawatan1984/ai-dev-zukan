require "test_helper"

class AdminResourceWorkflowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Taxonomy::SyncVocabulary.call
  end

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

    patch admin_resource_revision_path(revision), params: {
      resource_revision: {
        title: revision.title,
        author_name: revision.author_name,
        ai_summary: revision.ai_summary,
        capabilities: [ "GitHubから情報を取得する" ],
        key_points: [ "管理画面から分類を確定できる" ],
        suggested_category_slugs: [ "automation-integration", "ai-llm-agents" ],
        suggested_tag_slugs: [ "github", "api-integration", "ruby" ],
        search_keywords: [ "manual import" ]
      }
    }

    assert_redirected_to admin_resource_revision_path(revision)
    assert_equal [ "automation-integration", "ai-llm-agents" ], revision.reload.suggested_category_slugs
    assert_equal [ "github", "api-integration", "ruby" ], revision.suggested_tag_slugs
    assert_equal [ "manual import" ], revision.search_keywords
    assert_predicate revision, :taxonomy_origin_admin?
    assert_predicate revision, :review_pending?
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

  test "admin cannot save uncontrolled taxonomy and selected values remain visible" do
    sign_in users(:admin)
    revision = create_review_candidate

    patch admin_resource_revision_path(revision), params: {
      resource_revision: {
        title: revision.title,
        author_name: revision.author_name,
        ai_summary: revision.ai_summary,
        suggested_category_slugs: [ "automation-integration", "unknown-category" ],
        suggested_tag_slugs: [ "github", "unknown-tag" ]
      }
    }

    assert_response :unprocessable_content
    assert_select ".form-errors", /unknown category: unknown-category/
    assert_select ".form-errors", /unknown tag: unknown-tag/
    assert_select "input[name='resource_revision[suggested_category_slugs][]'][value='automation-integration'][checked]"
    assert_select "input[name='resource_revision[suggested_tag_slugs][]'][value='github'][checked]"
    assert_not_equal [ "automation-integration", "unknown-category" ], revision.reload.suggested_category_slugs
  end

  test "regular user receives the existing admin access response for revision review" do
    sign_in users(:regular)
    revision = create_review_candidate

    get edit_admin_resource_revision_path(revision)

    assert_redirected_to root_path
    assert_equal "管理者権限が必要です。", flash[:alert]
  end

  test "admin can approve a valid controlled candidate" do
    sign_in users(:admin)
    revision = create_review_candidate(
      suggested_category_slugs: [ "automation-integration" ],
      suggested_tag_slugs: [ "github", "api-integration" ]
    )

    post approve_and_publish_admin_resource_revision_path(revision)

    assert_redirected_to resource_path(revision.resource.slug)
    assert_predicate revision.reload, :approved?
    assert_equal [ "automation-integration" ], revision.resource.controlled_categories.pluck(:slug)
    assert_equal %w[github api-integration].sort, revision.resource.controlled_tags.pluck(:slug).sort
  end

  private

  def create_review_candidate(suggested_category_slugs: [], suggested_tag_slugs: [])
    resource = Resource.create!(
      kind: :mcp,
      slug: "admin-review-#{SecureRandom.hex(4)}",
      canonical_url: "https://github.com/example/admin-review-#{SecureRandom.hex(4)}",
      normalized_canonical_url: "https://github.com/example/admin-review-#{SecureRandom.hex(4)}",
      source_provider: :github,
      external_uid: SecureRandom.hex(8)
    )
    resource.revisions.create!(
      origin: :manual,
      title: "Admin Review Candidate",
      author_name: "example",
      source_excerpt: "Source excerpt",
      source_fingerprint: SecureRandom.hex(16),
      ai_summary: "GitHub APIと連携するMCPサーバーです。",
      summary_status: :manually_written,
      review_status: :review_pending,
      taxonomy_status: :succeeded,
      taxonomy_origin: :ai,
      taxonomy_provider: "nvidia",
      taxonomy_model: "test-taxonomizer",
      taxonomy_prompt_version: "taxonomy-v2",
      taxonomy_input_sha256: Digest::SHA256.hexdigest("taxonomy"),
      suggested_category_slugs:,
      suggested_tag_slugs:
    )
  end
end
