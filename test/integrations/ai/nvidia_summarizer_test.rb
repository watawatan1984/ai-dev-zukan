require "test_helper"

class Ai::NvidiaSummarizerTest < ActiveSupport::TestCase
  test "uses the OpenAI-compatible chat endpoint and parses structured output" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do |environment|
        assert_equal "Bearer test-key", environment.request_headers.fetch("Authorization")
        request = JSON.parse(environment.body)
        assert_equal "nvidia/nemotron-3-ultra-test", request.fetch("model")
        assert_equal false, request.fetch("stream")
        assert_equal "none", request.fetch("reasoning_effort")
        assert_includes request.dig("messages", 0, "content"), "信頼できない外部データ"
        assert_includes request.dig("messages", 1, "content"), "source_data_json"

        [
          200,
          { "Content-Type" => "application/json" },
          {
            choices: [ {
              message: {
                content: {
                  summary: "GitHub操作を効率化します。",
                  capabilities: [ "Issue検索" ],
                  key_points: [ "トークンが必要" ],
                  suggested_category_slug: "developer-tools",
                  suggested_tag_slugs: [ "github" ]
                }.to_json
              }
            } ]
          }.to_json
        ]
      end
    end
    connection = Faraday.new(url: "https://integrate.api.nvidia.com") do |faraday|
      faraday.adapter :test, stubs
    end
    summarizer = Ai::NvidiaSummarizer.new(
      api_key: "test-key",
      model: "nvidia/nemotron-3-ultra-test",
      endpoint: "/v1/chat/completions",
      connection:
    )

    result = summarizer.call(title: "GitHub MCP", source_excerpt: "README excerpt")

    assert_equal "GitHub操作を効率化します。", result.summary
    assert_equal [ "Issue検索" ], result.capabilities
    assert_equal "nvidia/nemotron-3-ultra-test", result.model
    stubs.verify_stubbed_calls
  end

  test "omits Nemotron specific reasoning controls for other models" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do |request|
        body = JSON.parse(request.body)
        refute body.key?("reasoning_effort")
        assert_equal 1_600, body.fetch("max_tokens")
        [ 200, { "Content-Type" => "application/json" }, { choices: [ { message: { content: { summary: "要約" }.to_json } } ] }.to_json ]
      end
    end
    connection = Faraday.new(url: "https://integrate.api.nvidia.com") do |faraday|
      faraday.adapter :test, stubs
    end
    summarizer = Ai::NvidiaSummarizer.new(
      api_key: "test-key",
      model: "openai/gpt-oss-120b",
      endpoint: "/v1/chat/completions",
      connection: connection
    )

    assert_equal "openai/gpt-oss-120b", summarizer.call(title: "Title", source_excerpt: "Excerpt").model
    stubs.verify_stubbed_calls
  end

  test "extracts a JSON object when the model wraps it in explanatory text" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do
        content = <<~CONTENT
          Here is the requested result.
          {"summary":"要約です。","capabilities":[],"key_points":[],"suggested_category_slug":"ai","suggested_tag_slugs":[]}
        CONTENT

        [
          200,
          { "Content-Type" => "application/json" },
          { choices: [ { message: { content: content } } ] }.to_json
        ]
      end
    end
    connection = Faraday.new(url: "https://integrate.api.nvidia.com") do |faraday|
      faraday.adapter :test, stubs
    end
    summarizer = Ai::NvidiaSummarizer.new(
      api_key: "test-key",
      model: "vendor/model-under-test",
      endpoint: "/v1/chat/completions",
      connection: connection
    )

    result = summarizer.call(title: "Title", source_excerpt: "Excerpt")

    assert_equal "要約です。", result.summary
    stubs.verify_stubbed_calls
  end

  test "bounds generated text before storing it" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do
        payload = {
          summary: "長" * 300,
          capabilities: [ "機能" * 150 ],
          key_points: [],
          suggested_category_slug: "ai",
          suggested_tag_slugs: []
        }
        [ 200, { "Content-Type" => "application/json" }, { choices: [ { message: { content: payload.to_json } } ] }.to_json ]
      end
    end
    connection = Faraday.new(url: "https://integrate.api.nvidia.com") do |faraday|
      faraday.adapter :test, stubs
    end
    summarizer = Ai::NvidiaSummarizer.new(
      api_key: "test-key",
      model: "vendor/model-under-test",
      endpoint: "/v1/chat/completions",
      connection: connection
    )

    result = summarizer.call(title: "Title", source_excerpt: "Excerpt")

    assert_operator result.summary.length, :<=, 180
    assert_operator result.capabilities.first.length, :<=, 200
  end

  test "accepts the numbered primary credentials from the local env file" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do |request|
        assert_equal "Bearer numbered-key", request.request_headers.fetch("Authorization")
        assert_equal "nvidia/numbered-model", JSON.parse(request.body).fetch("model")

        [
          200,
          { "Content-Type" => "application/json" },
          { choices: [ { message: { content: { summary: "要約" }.to_json } } ] }.to_json
        ]
      end
    end
    connection = Faraday.new(url: "https://integrate.api.nvidia.com") do |faraday|
      faraday.adapter :test, stubs
    end
    summarizer = Ai::NvidiaSummarizer.new(
      endpoint: "/v1/chat/completions",
      connection: connection,
      environment: {
        "NVIDIA_API_KEY1" => "numbered-key",
        "NVIDIA_AI_MODEL1" => "nvidia/numbered-model"
      }
    )

    result = summarizer.call(title: "Title", source_excerpt: "Excerpt")

    assert_equal "nvidia/numbered-model", result.model
    stubs.verify_stubbed_calls
  end
end
