require "test_helper"

class AppHostTest < ActiveSupport::TestCase
  test "explicit app host wins over Render default hostname" do
    environment = {
      "APP_HOST" => "catalog.example.com",
      "RENDER_EXTERNAL_HOSTNAME" => "ai-dev-zukan.onrender.com"
    }

    assert_equal "catalog.example.com", AppHost.resolve(environment)
  end

  test "uses Render default hostname when no custom host is configured" do
    environment = { "RENDER_EXTERNAL_HOSTNAME" => "ai-dev-zukan.onrender.com" }

    assert_equal "ai-dev-zukan.onrender.com", AppHost.resolve(environment)
  end

  test "falls back to localhost outside Render" do
    assert_equal "localhost", AppHost.resolve({})
  end
end
