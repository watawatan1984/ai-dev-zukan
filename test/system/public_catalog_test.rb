require "application_system_test_case"

class PublicCatalogTest < ApplicationSystemTestCase
  test "visitor can open and search the public catalog" do
    visit root_path

    assert_text "次に使うMCP・Skill・技術記事を、"
    assert_field "リソースを検索"

    fill_in "リソースを検索", with: "GitHub"
    click_on "検索"

    assert_current_path resources_path, ignore_query: true
    assert_text "“GitHub” の検索結果"
  end
end
