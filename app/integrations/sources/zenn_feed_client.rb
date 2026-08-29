require "rss"

module Sources
  class ZennFeedClient
    Entry = Data.define(:id, :title, :url, :author, :summary, :published_at, :updated_at)

    def initialize(
      http: HttpClient.new,
      feed_url: ENV.fetch("ZENN_FEED_URL", "https://zenn.dev/topics/ai/feed")
    )
      @http = http
      @feed_url = feed_url
    end

    def entries(limit:)
      feed = RSS::Parser.parse(http.get_text(feed_url), false)
      feed.items.first(limit).map { |item| build_entry(item) }
    rescue RSS::Error => error
      raise ProviderError, "Invalid Zenn RSS: #{error.message}"
    end

    private

    attr_reader :http, :feed_url

    def build_entry(item)
      Entry.new(
        id: item.guid&.content.presence || item.link,
        title: item.title,
        url: item.link,
        author: item.respond_to?(:dc_creator) ? item.dc_creator : nil,
        summary: ActionView::Base.full_sanitizer.sanitize(item.description.to_s).squish.truncate(2_000),
        published_at: item.pubDate,
        updated_at: item.respond_to?(:dc_date) ? item.dc_date : item.pubDate
      )
    end
  end
end
