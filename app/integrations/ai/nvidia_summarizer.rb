module Ai
  class NvidiaSummarizer
    class ConfigurationError < StandardError; end
    class ProviderError < StandardError; end

    ENDPOINT = "https://integrate.api.nvidia.com/v1/chat/completions".freeze
    PROMPT_VERSION = "catalog-summary-v1".freeze

    def initialize(
      api_key: nil,
      model: nil,
      endpoint: nil,
      connection: nil,
      environment: ENV
    )
      @api_key = api_key.presence || environment["NVIDIA_API_KEY"].presence || environment["NVIDIA_API_KEY1"]
      @model = model.presence || environment["NVIDIA_NIM_MODEL"].presence || environment["NVIDIA_AI_MODEL1"]
      @endpoint = endpoint.presence || environment["NVIDIA_NIM_ENDPOINT"].presence || ENDPOINT
      @connection = connection || default_connection
    end

    def call(title:, source_excerpt:)
      validate_configuration!
      response = connection.post(endpoint) do |request|
        request.headers["Authorization"] = "Bearer #{api_key}"
        request.headers["Accept"] = "application/json"
        request.headers["Content-Type"] = "application/json"
        request.body = request_body(title:, source_excerpt:).to_json
      end
      raise ProviderError, "NVIDIA NIM returned HTTP #{response.status}" unless response.success?

      payload = JSON.parse(response.body)
      content = payload.dig("choices", 0, "message", "content")
      raise ProviderError, "NVIDIA NIM response did not contain message content" if content.blank?

      build_summary(parse_json_content(content))
    rescue JSON::ParserError => error
      raise ProviderError, "NVIDIA NIM returned invalid JSON: #{error.message}"
    end

    private

    attr_reader :api_key, :model, :endpoint, :connection

    def validate_configuration!
      raise ConfigurationError, "NVIDIA_API_KEY is not configured" if api_key.blank?
      raise ConfigurationError, "NVIDIA_NIM_MODEL is not configured" if model.blank?
    end

    def default_connection
      Faraday.new do |faraday|
        faraday.options.open_timeout = 5
        faraday.options.timeout = 45
      end
    end

    def request_body(title:, source_excerpt:)
      {
        model: model,
        stream: false,
        temperature: 0.2,
        max_tokens: 700,
        messages: [
          {
            role: "system",
            content: "あなたは日本語の技術編集者です。推測を避け、入力に書かれた事実だけをJSONで返してください。"
          },
          {
            role: "user",
            content: <<~PROMPT
              次の技術リソースを日本語で整理してください。
              title: #{title}
              source excerpt:
              #{source_excerpt.to_s.truncate(12_000)}

              JSON schema:
              {"summary":"180文字以内", "capabilities":["最大5件"], "key_points":["注意点を最大5件"], "suggested_category_slug":"英小文字slug", "suggested_tag_slugs":["最大5件のslug"]}
            PROMPT
          }
        ]
      }
    end

    def parse_json_content(content)
      JSON.parse(content.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, ""))
    end

    def build_summary(payload)
      Ai::Summary.new(
        summary: payload.fetch("summary"),
        capabilities: Array(payload["capabilities"]).first(5),
        key_points: Array(payload["key_points"]).first(5),
        suggested_category_slug: payload["suggested_category_slug"],
        suggested_tag_slugs: Array(payload["suggested_tag_slugs"]).first(5),
        provider: "nvidia",
        model: model,
        prompt_version: PROMPT_VERSION,
        basis: "source excerpt"
      )
    end
  end
end
