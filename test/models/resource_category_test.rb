require "test_helper"

class ResourceCategoryTest < ActiveSupport::TestCase
  test "does not allow a duplicate resource and category pair" do
    resource = Resource.create!(
      kind: :mcp,
      source_provider: :manual,
      slug: "one",
      canonical_url: "https://example.com/one",
      normalized_canonical_url: "https://example.com/one"
    )
    category = Category.create!(slug: "coding-development", name: "コード作成・開発支援")
    ResourceCategory.create!(resource:, category:, origin: :admin)

    duplicate = ResourceCategory.new(resource:, category:, origin: :ai)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:category_id, :taken)
  end
end
