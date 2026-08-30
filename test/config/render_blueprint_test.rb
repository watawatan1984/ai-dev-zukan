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

  test "uses one Supabase database connection" do
    blueprint = YAML.safe_load_file(Rails.root.join("render.yaml"))
    service = blueprint.fetch("services").find { |entry| entry.fetch("name") == "ai-dev-zukan" }
    database_keys = service.fetch("envVars").filter_map do |entry|
      entry.fetch("key") if entry.fetch("key").end_with?("DATABASE_URL")
    end

    assert_equal [ "DATABASE_URL" ], database_keys
  end

  test "publishes the approved initial catalog during the first deploy hook" do
    blueprint = YAML.safe_load_file(Rails.root.join("render.yaml"))
    service = blueprint.fetch("services").find { |entry| entry.fetch("name") == "ai-dev-zukan" }
    release_confirmation = service.fetch("envVars").find do |entry|
      entry.fetch("key") == "INITIAL_CATALOG_RELEASE"
    end

    assert_includes service.fetch("initialDeployHook"), "catalog:bootstrap:release"
    assert_equal "publish", release_confirmation.fetch("value")
  end
end
