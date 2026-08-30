module Sources
  class GithubClient
    API_ROOT = "https://api.github.com".freeze

    def initialize(http: HttpClient.new, token: ENV["GITHUB_TOKEN"])
      @http = http
      @token = token
    end

    def search_repositories(query:, limit:, page: 1)
      per_page = limit.to_i.clamp(1, 100)
      payload = http.get_json(
        "#{API_ROOT}/search/repositories",
        params: { q: query, sort: "stars", order: "desc", per_page: per_page, page: page.to_i.clamp(1, 10) },
        headers: headers
      )
      payload.fetch("items")
    end

    def readme(full_name:)
      http.get_text(
        "#{API_ROOT}/repos/#{full_name}/readme",
        headers: headers.merge("Accept" => "application/vnd.github.raw+json")
      ).truncate(12_000)
    rescue ProviderError
      nil
    end

    private

    attr_reader :http, :token

    def headers
      {
        "Accept" => "application/vnd.github+json",
        "X-GitHub-Api-Version" => "2022-11-28",
        "User-Agent" => "ai-dev-zukan"
      }.tap do |values|
        values["Authorization"] = "Bearer #{token}" if token.present?
      end
    end
  end
end
