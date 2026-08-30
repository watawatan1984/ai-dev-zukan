require "test_helper"

class Taxonomy::RegistryTest < ActiveSupport::TestCase
  setup { Taxonomy::SyncVocabulary.call }

  test "exposes exactly the fourteen approved categories in display order" do
    assert_equal 14, Taxonomy::Registry.categories.size
    assert_equal "coding-development", Taxonomy::Registry.categories.first.fetch("slug")
    assert_equal "learning-career", Taxonomy::Registry.categories.last.fetch("slug")
  end

  test "resolves aliases without inventing a tag" do
    assert_equal "ruby-on-rails", Taxonomy::Registry.resolve_tag_slug("Rails")
    assert_equal "mcp", Taxonomy::Registry.resolve_tag_slug("model-context-protocol")
    assert_nil Taxonomy::Registry.resolve_tag_slug("one-off-product-2026")
  end
end
