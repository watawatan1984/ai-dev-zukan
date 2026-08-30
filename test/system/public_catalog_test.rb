require "application_system_test_case"

class PublicCatalogTest < ApplicationSystemTestCase
  test "visitor can open and search the public catalog" do
    visit root_path

    assert_text "次に使うMCP・Skill・技術記事を、"
    search_field = find('input[aria-label="リソースを検索"]')

    search_field.fill_in with: "GitHub"
    click_on "検索"

    assert_current_path resources_path, ignore_query: true
    assert_text "“GitHub” の検索結果"
  end
end
