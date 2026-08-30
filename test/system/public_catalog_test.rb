require "application_system_test_case"

class PublicCatalogTest < ApplicationSystemTestCase
  setup do
    Taxonomy::SyncVocabulary.call
    publish_resource(
      slug: "system-ruby-mcp",
      title: "System Ruby MCP",
      summary: "RubyとMCPの連携です。",
      kind: :mcp,
      source_provider: :github,
      categories: [ "automation-integration", "coding-development" ],
      tags: [ "ruby", "ruby-on-rails" ]
    )
    publish_resource(
      slug: "system-zenn-python",
      title: "System Zenn Python",
      summary: "PythonのZenn記事です。",
      kind: :zenn_article,
      source_provider: :zenn,
      categories: [ "research-search" ],
      tags: [ "python", "mcp" ]
    )
  end

  test "visitor can open and search the public catalog" do
    visit root_path

    assert_text "次に使うMCP・Skill・技術記事を、"
    search_field = find('input[aria-label="リソースを検索"]')

    search_field.fill_in with: "GitHub"
    click_on "検索"

    assert_current_path resources_path, ignore_query: true
    assert_text "“GitHub” の検索結果"
  end

  test "desktop filters keep actions reachable and support keyboard selection" do
    page.current_window.resize_to(1280, 720)
    visit resources_path

    assert_selector "[data-filter-actions]", visible: true
    assert_no_selector ".filter-panel[role='dialog']", visible: true

    find("label", text: "MCP").send_keys(:space)
    find("label", text: "Ruby").send_keys(:space)
    click_on "適用する"

    assert_current_path resources_path, ignore_query: true
    assert_text "System Ruby MCP"
    assert_text "一致タグ"
  end

  test "mobile filter sheet opens filters tags and closes accessibly" do
    page.current_window.resize_to(390, 844)
    visit resources_path

    opener = find_button("絞り込み")
    opener.native.focus
    click_on "絞り込み"
    assert_selector "[role='dialog'][aria-modal='true']", visible: true
    assert_equal "filters-title", page.evaluate_script("document.activeElement.id")
    assert page.evaluate_script("document.body.classList.contains('filter-sheet-open')")

    fill_in "タグを検索", with: "Rails"
    assert_selector "[data-tag-option]", text: "Ruby on Rails", visible: true
    assert_no_selector "[data-tag-option]", text: "Python", visible: true

    find("label", text: "Blog").send_keys(:space)
    assert_selector "[data-source-filter]", visible: true
    find("label", text: "Zenn").send_keys(:space)
    assert_selector "[data-mobile-filter-actions]", visible: true
    click_on "結果を見る"

    assert_current_path resources_path, ignore_query: true
    assert_text "System Zenn Python"

    click_on "絞り込み"
    assert_selector "[role='dialog'][aria-modal='true']", visible: true
    find("body").send_keys(:escape)
    assert_no_selector "[role='dialog'][aria-modal='true']", visible: true
    assert_equal "絞り込み", page.evaluate_script("document.activeElement.textContent.trim()")
    assert_not page.evaluate_script("document.body.classList.contains('filter-sheet-open')")
  end

  test "mobile backdrop closes and hidden source checkboxes are not submitted" do
    page.current_window.resize_to(390, 844)
    visit resources_path(content_types: [ "blog" ], sources: [ "zenn" ])

    click_on "絞り込み"
    assert_selector "[role='dialog'][aria-modal='true']", visible: true
    assert_selector "#source-zenn", checked: true, visible: :all

    find("label", text: "Blog").send_keys(:space)
    assert page.has_css?("[data-source-filter][hidden]", visible: :all)
    assert page.evaluate_script("document.querySelector('#source-zenn').disabled")
    assert_text "0件選択中"

    click_on "結果を見る"

    assert_current_path resources_path, ignore_query: true
    assert_no_current_path(/sources/)

    click_on "絞り込み"
    assert_selector "[role='dialog'][aria-modal='true']", visible: true
    find(".filter-backdrop", visible: :all).click
    assert_no_selector "[role='dialog'][aria-modal='true']", visible: true
  end

  test "active filter chips clear one value or all filters" do
    visit resources_path(content_types: [ "mcp", "blog" ], tag_slugs: [ "ruby" ])

    within("[data-active-filters]") do
      click_on "MCP"
    end

    assert_current_path(/content_types%5B%5D=blog/)
    assert_current_path(/tag_slugs%5B%5D=ruby/)

    click_on "すべて解除"

    assert_current_path resources_path, ignore_query: true
  end

  test "visitor can switch light and dark theme" do
    visit resources_path

    select "ダーク", from: "表示テーマ"
    assert_equal "dark", page.evaluate_script("document.documentElement.dataset.theme")

    select "ライト", from: "表示テーマ"
    assert_equal "light", page.evaluate_script("document.documentElement.dataset.theme")
  end

  private

  def publish_resource(slug:, title:, summary:, kind:, source_provider:, categories:, tags:)
    resource = Resource.create!(
      kind: kind,
      slug: slug,
      canonical_url: "https://example.com/#{slug}",
      normalized_canonical_url: "https://example.com/#{slug}",
      source_provider: source_provider,
      external_uid: slug,
      source_published_at: Time.current
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: title,
      ai_summary: summary,
      source_fingerprint: "#{slug}-v1",
      summary_status: :succeeded,
      review_status: :approved,
      suggested_category_slugs: categories,
      suggested_tag_slugs: tags
    )
    resource.publish!(revision: revision)
    categories.each do |category_slug|
      resource.resource_categories.create!(category: Category.find_by!(slug: category_slug), origin: :ai)
    end
    tags.each do |tag_slug|
      resource.controlled_resource_tags.create!(tag: Tag.find_by!(slug: tag_slug), origin: :ai)
    end
    resource
  end
end
