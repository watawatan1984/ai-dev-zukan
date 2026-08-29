module Sources
  class QiitaClient
    ITEMS_URL = "https://qiita.com/api/v2/items".freeze

    def initialize(http: HttpClient.new, token: ENV["QIITA_ACCESS_TOKEN"])
      @http = http
      @token = token
    end

    def items(limit:)
      http.get_json(
        ITEMS_URL,
        params: {
          page: 1,
          per_page: limit,
          query: ENV.fetch("QIITA_IMPORT_QUERY", "stocks:>=10")
        },
        headers: headers
      )
    end

    private

    attr_reader :http, :token

    def headers
      { "User-Agent" => "ai-dev-zukan" }.tap do |values|
        values["Authorization"] = "Bearer #{token}" if token.present?
      end
    end
  end
end
