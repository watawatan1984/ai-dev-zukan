require "test_helper"
require Rails.root.join("db/migrate/20260831084500_deactivate_legacy_categories")

class DeactivateLegacyCategoriesTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "deactivates legacy categories without deleting them or hiding controlled categories" do
    controlled = Category.find_by!(slug: "coding-development")
    legacy = Category.create!(
      slug: "legacy-generated-category",
      name: "Legacy Generated Category",
      position: 0,
      active: true
    )

    migration = DeactivateLegacyCategories.new
    migration.suppress_messages { migration.up }

    assert_predicate controlled.reload, :active?
    assert_not legacy.reload.active?
    assert Category.exists?(legacy.id)

    migration.suppress_messages { migration.down }
    assert_predicate legacy.reload, :active?
  end
end
