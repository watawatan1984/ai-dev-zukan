require "test_helper"

class Sources::ZennFeedClientTest < ActiveSupport::TestCase
  class FakeHttp
    def initialize(feeds)
      @feeds = feeds
    end

    def get_text(url)
      @feeds.fetch(url)
    end
  end

  test "round robins multiple feeds and removes duplicate articles" do
    first_url = "https://zenn.dev/feed"
    second_url = "https://zenn.dev/topics/ruby/feed"
    shared = rss_item("shared", published_at: "Sat, 29 Aug 2026 10:00:00 +0900")
    feeds = {
      first_url => rss(shared, rss_item("first", published_at: "Fri, 28 Aug 2026 10:00:00 +0900")),
      second_url => rss(shared, rss_item("second", published_at: "Thu, 27 Aug 2026 10:00:00 +0900"))
    }
    client = Sources::ZennFeedClient.new(
      http: FakeHttp.new(feeds),
      feed_urls: [ first_url, second_url ]
    )

    entries = client.entries(limit: 3)

    assert_equal [ "shared", "first", "second" ], entries.map(&:id)
  end

  private

  def rss(*items)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Zenn</title>
          <link>https://zenn.dev</link>
          <description>Zenn feed</description>
          #{items.join}
        </channel>
      </rss>
    XML
  end

  def rss_item(id, published_at:)
    <<~XML
      <item>
        <guid>#{id}</guid>
        <title>#{id} title</title>
        <link>https://zenn.dev/example/articles/#{id}</link>
        <description>#{id} summary</description>
        <pubDate>#{published_at}</pubDate>
      </item>
    XML
  end
end
