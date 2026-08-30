module Ai
  class NvidiaTaxonomizer
    class ConfigurationError < StandardError; end
    class ProviderError < StandardError; end

    ENDPOINT = Ai::NvidiaSummarizer::ENDPOINT
    PROMPT_VERSION = "catalog-taxonomy-v2.1".freeze

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

    def call(revision:)
      validate_configuration!
      response = connection.post(endpoint) do |request|
        request.headers["Authorization"] = "Bearer #{api_key}"
        request.headers["Accept"] = "application/json"
        request.headers["Content-Type"] = "application/json"
        request.body = request_body(revision:).to_json
      end
      raise ProviderError, "NVIDIA NIM returned HTTP #{response.status}" unless response.success?

      payload = JSON.parse(response.body)
      content = payload.dig("choices", 0, "message", "content")
      raise ProviderError, "NVIDIA NIM response did not contain message content" if content.blank?

      build_suggestion(revision:, payload: parse_json_content(content))
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

    def request_body(revision:)
      {
        model: model,
        stream: false,
        temperature: 0,
        max_tokens: model.start_with?("openai/gpt-oss") ? 1_200 : 500,
        messages: [
          {
            role: "system",
            content: "You classify catalog resources using only supplied allowlists. Values outside the supplied allowlists are invalid. Return only one JSON object matching the requested schema. No explanation, prose, Markdown, or code fences."
          },
          {
            role: "user",
            content: <<~PROMPT
              Classify this resource for AI開発図鑑.
              taxonomy_registry_json:
              #{Taxonomy::Registry.prompt_payload.to_json}

              classification_basis_json:
              #{classification_basis(revision).to_json}

              Selection rules:
              - Do not use a tag that restates the resource kind.
              - For kind=mcp, do not include tag_slug "mcp".
              - For kind=skill, do not include tag_slug "agent-skills".
              - Prefer tags that describe language, platform, tool, technique, or runtime.

              JSON schema:
              {"category_slugs":["1-3 category slugs from taxonomy_registry_json.categories"],"tag_slugs":["2-6 tag slugs or aliases from taxonomy_registry_json.tags"],"search_keywords":["optional search phrases, max 30"],"confidence":0.0}
            PROMPT
          }
        ]
      }.tap do |body|
        body[:reasoning_effort] = "none" if model.start_with?("nvidia/nemotron-3-ultra")
      end
    end

    def classification_basis(revision)
      {
        title: revision.title,
        source_excerpt: revision.source_excerpt.to_s.truncate(12_000),
        summary: revision.ai_summary.to_s,
        capabilities: Array(revision.capabilities),
        key_points: Array(revision.key_points)
      }
    end

    def parse_json_content(content)
      normalized = content.to_s.strip
      parsed = JSON.parse(normalized)
      raise ProviderError, "NVIDIA NIM returned non-object taxonomy JSON" unless parsed.is_a?(Hash)

      parsed
    end

    def build_suggestion(revision:, payload:)
      confidence = payload.fetch("confidence")
      raise ProviderError, "NVIDIA NIM returned confidence outside 0.0-1.0" unless confidence.is_a?(Numeric) && confidence.between?(0, 1)

      suggestion = Ai::TaxonomySuggestion.new(
        category_slugs: bounded_slug_list(payload.fetch("category_slugs"), "category_slugs"),
        tag_slugs: normalized_tag_slugs(revision, payload.fetch("tag_slugs")),
        search_keywords: bounded_search_keywords(payload.fetch("search_keywords")),
        confidence: confidence.to_f,
        provider: "nvidia",
        model: model,
        prompt_version: PROMPT_VERSION
      )
      validation = Taxonomy::ValidateSuggestion.call(revision: validation_revision(revision, suggestion))
      raise ProviderError, "NVIDIA NIM returned invalid taxonomy suggestion" unless validation.valid?

      suggestion.with(
        category_slugs: validation.category_slugs,
        tag_slugs: validation.tag_slugs,
        search_keywords: validation.search_keywords
      )
    rescue KeyError => error
      raise ProviderError, "NVIDIA NIM taxonomy JSON missing #{error.key}"
    end

    def validation_revision(revision, suggestion)
      revision.dup.tap do |candidate|
        candidate.resource = revision.resource
        candidate.suggested_category_slugs = suggestion.category_slugs
        candidate.suggested_tag_slugs = suggestion.tag_slugs
        candidate.search_keywords = suggestion.search_keywords
      end
    end

    def bounded_slug_list(values, field)
      raise ProviderError, "NVIDIA NIM taxonomy JSON #{field} must be an array" unless values.is_a?(Array)

      Array(values).filter_map { |value| value.to_s.unicode_normalize(:nfkc).strip.downcase.presence }
    end

    def normalized_tag_slugs(revision, values)
      bounded_slug_list(values, "tag_slugs").reject do |slug|
        (revision.resource.kind_mcp? && slug == "mcp") ||
          (revision.resource.kind_skill? && slug == "agent-skills")
      end
    end

    def bounded_search_keywords(values)
      raise ProviderError, "NVIDIA NIM taxonomy JSON search_keywords must be an array" unless values.is_a?(Array)

      Array(values).filter_map { |value| Search::Normalize.call(value).presence }
    end
  end
end
