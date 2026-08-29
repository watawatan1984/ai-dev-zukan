require "test_helper"

class Sources::QiitaCatalogTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:records) do
    def items(limit:)
      records.first(limit)
    end
  end

  test "maps a Qiita item without retaining the full article body" do
    item = {
      "id" => "qiita-123",
      "title" => "Rails 8のジョブ設計",
      "url" => "https://qiita.com/example/items/qiita-123",
      "user" => { "id" => "example" },
      "created_at" => "2026-07-01T01:02:03+09:00",
      "updated_at" => "2026-07-02T01:02:03+09:00",
      "likes_count" => 88,
      "body" => "a" * 5_000
    }

    snapshot = Sources::QiitaCatalog.new(client: FakeClient.new([ item ])).fetch(limit: 10).sole

    assert_equal :qiita_article, snapshot.kind
    assert_equal :qiita, snapshot.provider
    assert_equal "qiita-123", snapshot.external_uid
    assert_operator snapshot.excerpt.length, :<=, 2_000
    assert_equal 88, snapshot.popularity_raw
  end

  test "like count changes update popularity without creating a content revision" do
    item = {
      "id" => "qiita-123",
      "title" => "Rails 8のジョブ設計",
      "url" => "https://qiita.com/example/items/qiita-123",
      "user" => { "id" => "example" },
      "updated_at" => "2026-07-02T01:02:03+09:00",
      "likes_count" => 88,
      "body" => "same body"
    }
    first = Sources::QiitaCatalog.new(client: FakeClient.new([ item ])).fetch(limit: 1).sole
    item["likes_count"] = 89
    second = Sources::QiitaCatalog.new(client: FakeClient.new([ item ])).fetch(limit: 1).sole

    assert_equal first.source_fingerprint, second.source_fingerprint
    refute_equal first.popularity_raw, second.popularity_raw
  end
end
