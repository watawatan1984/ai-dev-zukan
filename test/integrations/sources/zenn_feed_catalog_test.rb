require "test_helper"

class Sources::ZennFeedCatalogTest < ActiveSupport::TestCase
  Entry = Data.define(:id, :title, :url, :author, :summary, :published_at, :updated_at)
  FakeClient = Struct.new(:records) do
    def entries(limit:)
      records.first(limit)
    end
  end

  test "maps a Zenn RSS entry to a source snapshot" do
    published_at = Time.zone.local(2026, 8, 1, 10, 0)
    entry = Entry.new(
      id: "https://zenn.dev/example/articles/rails-jobs",
      title: "Railsの非同期処理",
      url: "https://zenn.dev/example/articles/rails-jobs",
      author: "example",
      summary: "Solid Queueの設計を解説します。",
      published_at: published_at,
      updated_at: published_at
    )

    snapshot = Sources::ZennFeedCatalog.new(client: FakeClient.new([ entry ])).fetch(limit: 10).sole

    assert_equal :zenn_article, snapshot.kind
    assert_equal :zenn, snapshot.provider
    assert_equal entry.id, snapshot.external_uid
    assert_equal entry.summary, snapshot.excerpt
    assert_equal published_at, snapshot.source_published_at
  end
end
