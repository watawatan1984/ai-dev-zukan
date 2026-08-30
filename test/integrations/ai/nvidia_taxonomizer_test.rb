require "test_helper"

class Ai::NvidiaTaxonomizerTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "sends only classification basis and controlled taxonomy payload" do
    revision = build_revision(
      title: "Solid Queue Guide",
      source_excerpt: "RailsでSolid Queueを使う記事です。",
      ai_summary: "Railsの非同期処理を解説します。",
      capabilities: [ "ジョブ実行" ],
      key_points: [ "PostgreSQLが必要" ]
    )
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do |environment|
        assert_equal "Bearer test-key", environment.request_headers.fetch("Authorization")
        request = JSON.parse(environment.body)
        assert_equal "nvidia/nemotron-3-ultra-test", request.fetch("model")
        assert_equal false, request.fetch("stream")
        assert_equal "none", request.fetch("reasoning_effort")
        assert_includes request.dig("messages", 0, "content"), "allowlists"
        user_content = request.dig("messages", 1, "content")
        assert_includes user_content, "taxonomy_registry_json"
        assert_includes user_content, "classification_basis_json"
        assert_includes user_content, "Solid Queue Guide"
        assert_includes user_content, Taxonomy::Registry.version
        refute_includes user_content, "canonical_url"
        refute_includes user_content, "source_fingerprint"

        [
          200,
          { "Content-Type" => "application/json" },
          {
            choices: [ {
              message: {
                content: {
                  category_slugs: [ "automation-integration" ],
                  tag_slugs: [ "ruby", "api-integration" ],
                  search_keywords: [ "Solid Queue" ],
                  confidence: 0.92
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
    taxonomizer = Ai::NvidiaTaxonomizer.new(
      api_key: "test-key",
      model: "nvidia/nemotron-3-ultra-test",
      endpoint: "/v1/chat/completions",
      connection:
    )

    result = taxonomizer.call(revision:)

    assert_equal [ "automation-integration" ], result.category_slugs
    assert_equal [ "ruby", "api-integration" ], result.tag_slugs
    assert_equal [ "solid queue" ], result.search_keywords
    assert_equal 0.92, result.confidence
    assert_equal "nvidia", result.provider
    assert_equal "nvidia/nemotron-3-ultra-test", result.model
    assert_equal "catalog-taxonomy-v2", result.prompt_version
    stubs.verify_stubbed_calls
  end

  test "rejects prose wrapped responses" do
    assert_provider_error_for("Here is the JSON:\n{\"category_slugs\":[\"automation-integration\"],\"tag_slugs\":[\"ruby\",\"api-integration\"],\"search_keywords\":[],\"confidence\":0.9}")
  end

  test "rejects unknown controlled slugs and excess counts" do
    content = {
      category_slugs: [ "automation-integration", "coding-development", "testing-quality", "unknown-category" ],
      tag_slugs: [ "ruby", "api-integration", "github", "testing", "docker", "rails", "unknown-tag" ],
      search_keywords: [],
      confidence: 0.9
    }.to_json

    assert_provider_error_for(content)
  end

  test "rejects malformed json and out of range confidence" do
    assert_provider_error_for("{not json")
    assert_provider_error_for({
      category_slugs: [ "automation-integration" ],
      tag_slugs: [ "ruby", "api-integration" ],
      search_keywords: [],
      confidence: 1.2
    }.to_json)
  end

  private

  def assert_provider_error_for(content)
    revision = build_revision
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/chat/completions") do
        [ 200, { "Content-Type" => "application/json" }, { choices: [ { message: { content: } } ] }.to_json ]
      end
    end
    connection = Faraday.new(url: "https://integrate.api.nvidia.com") do |faraday|
      faraday.adapter :test, stubs
    end
    taxonomizer = Ai::NvidiaTaxonomizer.new(
      api_key: "test-key",
      model: "vendor/model-under-test",
      endpoint: "/v1/chat/completions",
      connection:
    )

    assert_raises(Ai::NvidiaTaxonomizer::ProviderError) do
      taxonomizer.call(revision:)
    end
  end

  def build_revision(title: "Example", source_excerpt: "Excerpt", ai_summary: "Summary", capabilities: [], key_points: [])
    resource = Resource.create!(
      kind: :zenn_article,
      slug: "nvidia-taxonomizer-#{SecureRandom.hex(6)}",
      canonical_url: "https://example.com/#{SecureRandom.hex(6)}",
      normalized_canonical_url: "https://example.com/#{SecureRandom.hex(6)}",
      source_provider: :zenn
    )

    resource.revisions.create!(
      origin: :imported,
      title:,
      source_excerpt:,
      source_fingerprint: SecureRandom.hex(12),
      ai_summary:,
      capabilities:,
      key_points:,
      summary_status: :succeeded,
      taxonomy_status: :queued,
      review_status: :draft
    )
  end
end
