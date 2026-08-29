module Sources
  class HttpClient
    def initialize(connection: Faraday.new)
      @connection = connection
    end

    def get_json(url, params: {}, headers: {})
      response = connection.get(url, params, headers)
      ensure_success!(response, url)
      JSON.parse(response.body)
    rescue JSON::ParserError => error
      raise ProviderError, "Invalid JSON from #{url}: #{error.message}"
    end

    def get_text(url, params: {}, headers: {})
      response = connection.get(url, params, headers)
      ensure_success!(response, url)
      response.body
    end

    private

    attr_reader :connection

    def ensure_success!(response, url)
      return if response.success?

      raise ProviderError, "Source request failed with HTTP #{response.status}: #{url}"
    end
  end
end
