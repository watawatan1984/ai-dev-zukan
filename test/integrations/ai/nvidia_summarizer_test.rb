require "test_helper"

class Ai::NvidiaSummarizerTest < ActiveSupport::TestCase
  test "uses the OpenAI-compatible chat endpoint and parses structured output" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do |environment|
        assert_equal "Bearer test-key", environment.request_headers.fetch("Authorization")
        request = JSON.parse(environment.body)
        assert_equal "vendor/model-under-test", request.fetch("model")
        assert_equal false, request.fetch("stream")

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
      model: "vendor/model-under-test",
      endpoint: "/v1/chat/completions",
      connection:
    )

    result = summarizer.call(title: "GitHub MCP", source_excerpt: "README excerpt")

    assert_equal "GitHub操作を効率化します。", result.summary
    assert_equal [ "Issue検索" ], result.capabilities
    assert_equal "vendor/model-under-test", result.model
    stubs.verify_stubbed_calls
  end
end
