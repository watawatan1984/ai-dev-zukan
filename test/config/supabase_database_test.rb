require "test_helper"
require "erb"
require "yaml"

class SupabaseDatabaseTest < ActiveSupport::TestCase
  test "production uses one Supabase-compatible primary database" do
    previous = ENV["DATABASE_URL"]
    ENV["DATABASE_URL"] = "postgresql://session-pooler.example.test:5432/postgres?sslmode=require"
    rendered = ERB.new(Rails.root.join("config/database.yml").read).result
    database_config = YAML.safe_load(rendered, aliases: true).fetch("production")

    assert_equal [ "primary" ], database_config.keys
    assert_equal ENV["DATABASE_URL"], database_config.dig("primary", "url")
  ensure
    ENV["DATABASE_URL"] = previous
  end

  test "Solid Queue tables live in the primary database" do
    assert ActiveRecord::Base.connection.data_source_exists?("solid_queue_jobs")
    assert ActiveRecord::Base.connection.data_source_exists?("solid_queue_processes")
  end
end
