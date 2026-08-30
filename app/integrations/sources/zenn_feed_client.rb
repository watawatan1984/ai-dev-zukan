require "rss"

module Sources
  class ZennFeedClient
    Entry = Data.define(:id, :title, :url, :author, :summary, :published_at, :updated_at)
    DEFAULT_FEED_URLS = [
      "https://zenn.dev/feed",
      "https://zenn.dev/topics/ai/feed",
      "https://zenn.dev/topics/llm/feed",
      "https://zenn.dev/topics/mcp/feed",
      "https://zenn.dev/topics/claude/feed",
      "https://zenn.dev/topics/claudecode/feed",
      "https://zenn.dev/topics/codex/feed",
      "https://zenn.dev/topics/ruby/feed",
      "https://zenn.dev/topics/rails/feed",
      "https://zenn.dev/topics/python/feed",
      "https://zenn.dev/topics/typescript/feed",
      "https://zenn.dev/topics/javascript/feed",
      "https://zenn.dev/topics/react/feed",
      "https://zenn.dev/topics/nextjs/feed",
      "https://zenn.dev/topics/docker/feed",
      "https://zenn.dev/topics/aws/feed",
      "https://zenn.dev/topics/cloudflare/feed",
      "https://zenn.dev/topics/postgresql/feed",
      "https://zenn.dev/topics/openai/feed",
      "https://zenn.dev/topics/githubactions/feed"
    ].freeze

    def initialize(
      http: HttpClient.new,
      feed_url: nil,
      feed_urls: nil,
      environment: ENV
    )
      @http = http
      @feed_urls = resolve_feed_urls(feed_url:, feed_urls:, environment:)
    end

    def entries(limit:)
      entries_by_feed = feed_urls.filter_map do |url|
        parse_entries(url)
      rescue ProviderError => error
        Rails.logger.warn(error.message)
        nil
      end
      raise ProviderError, "All configured Zenn feeds failed" if entries_by_feed.empty?

      round_robin(entries_by_feed, limit:)
    end

    private

    attr_reader :http, :feed_urls

    def resolve_feed_urls(feed_url:, feed_urls:, environment:)
      return Array(feed_urls).compact_blank if feed_urls
      return [ feed_url ] if feed_url.present?

      configured = environment["ZENN_FEED_URLS"].to_s.split(",").map(&:strip).compact_blank
      return configured if configured.present?
      return [ environment["ZENN_FEED_URL"] ] if environment["ZENN_FEED_URL"].present?

      DEFAULT_FEED_URLS
    end

    def parse_entries(url)
      feed = RSS::Parser.parse(http.get_text(url), false)
      feed.items.map { |item| build_entry(item) }
    rescue RSS::Error => error
      raise ProviderError, "Invalid Zenn RSS from #{url}: #{error.message}"
    end

    def round_robin(entries_by_feed, limit:)
      seen = {}
      result = []
      largest_feed = entries_by_feed.map(&:length).max.to_i
      largest_feed.times do |index|
        entries_by_feed.each do |entries|
          entry = entries[index]
          next unless entry
          next if seen[entry.id]

          seen[entry.id] = true
          result << entry
          return result if result.length >= limit
        end
      end
      result
    end

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
