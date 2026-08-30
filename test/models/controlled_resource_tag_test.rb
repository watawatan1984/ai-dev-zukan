require "test_helper"

class ControlledResourceTagTest < ActiveSupport::TestCase
  test "coexists with legacy resource tags and keeps controlled uniqueness separate" do
    resource = Resource.create!(
      kind: :mcp,
      source_provider: :manual,
      slug: "controlled-tag-resource",
      canonical_url: "https://example.com/controlled-tag-resource",
      normalized_canonical_url: "https://example.com/controlled-tag-resource"
    )
    tag = Tag.create!(slug: "ruby-on-rails", name: "Ruby on Rails", normalized_name: "ruby on rails")

    ResourceTag.create!(resource:, tag:, origin: :source)
    ControlledResourceTag.create!(resource:, tag:, origin: :admin)

    assert_equal 1, resource.resource_tags.count
    assert_equal 1, resource.controlled_resource_tags.count

    duplicate = ControlledResourceTag.new(resource:, tag:, origin: :ai)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:tag_id, :taken)

    resource.controlled_resource_tags.destroy_all

    assert_equal 1, resource.resource_tags.count
    assert_equal 0, resource.controlled_resource_tags.count
  end
end
