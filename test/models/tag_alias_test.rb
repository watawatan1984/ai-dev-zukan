require "test_helper"

class TagAliasTest < ActiveSupport::TestCase
  test "does not allow duplicate normalized alias names" do
    tag = Tag.create!(slug: "ruby-on-rails", name: "Ruby on Rails", normalized_name: "ruby on rails")
    TagAlias.create!(tag:, name: "Rails", normalized_name: "rails")

    duplicate = TagAlias.new(tag:, name: "rails", normalized_name: "rails")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:normalized_name, :taken)
  end
end
