require "test_helper"

class Search::ResourcesQueryTest < ActiveSupport::TestCase
  test "query returns matching published resources and excludes unpublished candidates" do
    published = create_resource_with_revision(
      slug: "solid-queue-guide",
      title: "Solid Queue実践ガイド",
      summary: "Railsでバックグラウンドジョブを運用する方法を解説します。",
      review_status: :approved
    )
    published.publish!(revision: published.revisions.first)

    create_resource_with_revision(
      slug: "private-solid-queue-guide",
      title: "未公開のSolid Queue記事",
      summary: "この候補は検索結果に表示されません。",
      review_status: :review_pending
    )

    results = Search::ResourcesQuery.call(params: { q: "Solid Queue" })

    assert_equal [ published ], results.to_a
  end

  test "signed in user does not receive hidden resources" do
    user = users(:regular)
    resource = create_resource_with_revision(
      slug: "hidden-mcp",
      title: "Hidden MCP",
      summary: "非表示にするMCPです。",
      review_status: :approved
    )
    resource.publish!(revision: resource.revisions.first)
    user.hidden_resources.create!(resource: resource)

    results = Search::ResourcesQuery.call(params: {}, user: user)

    assert_empty results
  end

  private

  def create_resource_with_revision(slug:, title:, summary:, review_status:)
    resource = Resource.create!(
      kind: :qiita_article,
      slug: slug,
      canonical_url: "https://qiita.com/example/items/#{slug}",
      normalized_canonical_url: "https://qiita.com/example/items/#{slug}",
      source_provider: :qiita,
      external_uid: slug
    )
    resource.revisions.create!(
      origin: :imported,
      title: title,
      ai_summary: summary,
      source_fingerprint: "#{slug}-fingerprint",
      summary_status: :succeeded,
      review_status: review_status
    )
    resource
  end
end
