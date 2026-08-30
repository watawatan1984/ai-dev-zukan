require "test_helper"
require "yaml"

class RenderBlueprintTest < ActiveSupport::TestCase
  test "maps APP_HOST to Render's generated hostname" do
    blueprint = YAML.safe_load_file(Rails.root.join("render.yaml"))
    service = blueprint.fetch("services").find { |entry| entry.fetch("name") == "ai-dev-zukan" }
    app_host = service.fetch("envVars").find { |entry| entry.fetch("key") == "APP_HOST" }

    assert_equal({
      "type" => "web",
      "name" => "ai-dev-zukan",
      "envVarKey" => "RENDER_EXTERNAL_HOSTNAME"
    }, app_host.fetch("fromService"))
  end
end
