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

    focus_checkbox_by_tab("content-type-mcp")
    page.send_keys(:space)
    assert find("#content-type-mcp", visible: :all).checked?

    focus_checkbox_by_tab("category-automation-integration")
    page.send_keys(:space)
    assert find("#category-automation-integration", visible: :all).checked?

    focus_checkbox_by_tab("tag-ruby")
    page.send_keys(:space)
    assert find("#tag-ruby", visible: :all).checked?

    click_on "適用する"

    assert_current_path resources_path, ignore_query: true
    assert_text "System Ruby MCP"
    assert_text "一致タグ"
  end

  test "mobile filter sheet opens filters tags and closes accessibly" do
    page.current_window.resize_to(390, 844)
    visit resources_path

    opener = find_button("絞り込み")
    opener.send_keys(:enter)
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
    assert find("#source-zenn", visible: :all).checked?

    find("label", text: "Blog").send_keys(:space)
    assert page.has_css?("[data-source-filter][hidden]", visible: :all)
    assert page.evaluate_script("document.querySelector('#source-zenn').disabled")
    assert_text "0件選択中"

    click_on "結果を見る"

    assert_current_path resources_path, ignore_query: true
    assert_no_current_path(/[?&]sources(?:%5B%5D|\[\])?=/)

    click_on "絞り込み"
    assert_selector "[role='dialog'][aria-modal='true']", visible: true
    find(".filter-backdrop", visible: :all).click
    assert_no_selector "[role='dialog'][aria-modal='true']", visible: true
  end

  test "mobile open state is fully closed when resizing through desktop breakpoint" do
    page.current_window.resize_to(390, 844)
    visit resources_path

    click_on "絞り込み"
    assert_selector "[role='dialog'][aria-modal='true']", visible: true
    assert page.evaluate_script("document.body.classList.contains('filter-sheet-open')")

    page.current_window.resize_to(1280, 720)

    assert_no_selector ".filter-panel.is-open", visible: :all
    assert_no_selector ".filter-panel[role='dialog']", visible: :all
    assert_not page.evaluate_script("document.body.classList.contains('filter-sheet-open')")

    page.current_window.resize_to(390, 844)

    assert_no_selector ".filter-panel.is-open", visible: :all
    assert_no_selector ".filter-panel[role='dialog']", visible: :all
    assert_not page.evaluate_script("document.body.classList.contains('filter-sheet-open')")
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

  test "mobile filter opener is ready, traps focus, makes the catalog inert, and restores focus" do
    page.current_window.resize_to(390, 844)
    visit resources_path

    opener = find_button("絞り込み")
    assert_not opener.disabled?
    opener.send_keys(:enter)
    assert_selector "[role='dialog'][aria-modal='true']", visible: true
    assert_equal "filters-title", page.evaluate_script("document.activeElement.id")
    assert page.evaluate_script("document.querySelector('header').inert")
    assert page.evaluate_script("document.querySelector('.hero').inert")
    assert page.evaluate_script("document.querySelector('.results-panel').inert")

    page.evaluate_script("document.querySelector('[data-facet-filter-target=\"initialFocus\"]').focus()")
    page.send_keys(:tab)
    assert page.evaluate_script("document.querySelector('[role=\"dialog\"]:focus-within') !== null")
    30.times { page.send_keys(:tab) }
    assert page.evaluate_script("document.querySelector('[role=\"dialog\"]:focus-within') !== null")

    find("body").send_keys(:escape)
    assert_equal "絞り込み", page.evaluate_script("document.activeElement.textContent.trim()")
    assert_not page.evaluate_script("document.querySelector('header').inert")

    page.evaluate_script("sessionStorage.setItem('facet-filter:interaction', 'true')")
    page.evaluate_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    assert_nil page.evaluate_script("sessionStorage.getItem('facet-filter:interaction')")
    assert page.evaluate_script("document.querySelector('[data-facet-filter-target=\"openButton\"]').disabled")
  end

  test "mobile filter submission closes immediately and focuses results only after interaction navigation" do
    page.current_window.resize_to(390, 844)
    visit resources_path
    click_on "絞り込み"
    click_on "結果を見る"
    assert_no_selector "[role='dialog'][aria-modal='true']", visible: true
    assert_selector ".results-panel[aria-busy='false']", visible: true
    assert_equal "results-heading", page.evaluate_script("document.activeElement.id")

    visit resources_path(content_types: [ "mcp" ])
    assert_not_equal "results-heading", page.evaluate_script("document.activeElement.id")
  end

  test "mobile filter focus trap wraps at the sheet boundaries without focusing the backdrop" do
    page.current_window.resize_to(390, 844)
    visit resources_path
    click_on "絞り込み"

    page.execute_script(<<~JS)
      const focusables = Array.from(document.querySelector('.filter-sheet').querySelectorAll(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
      )).filter((element) => element.offsetParent !== null)
      focusables.at(-1).focus()
    JS
    page.send_keys(:tab)
    assert_equal "filters-title", page.evaluate_script("document.activeElement.id")
    assert_not_equal "filter-backdrop", page.evaluate_script("document.activeElement.className")

    page.evaluate_script("document.querySelector('[data-facet-filter-target=\"initialFocus\"]').focus()")
    page.send_keys(:shift, :tab)
    assert page.evaluate_script(<<~JS)
      (() => {
        const focusables = Array.from(document.querySelector('.filter-sheet').querySelectorAll(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
        )).filter((element) => element.offsetParent !== null)
        return document.activeElement === focusables.at(-1)
      })()
    JS
    assert_not_equal "filter-backdrop", page.evaluate_script("document.activeElement.className")
  end

  test "mobile filter submission exposes busy progress and prevents duplicate requests" do
    page.current_window.resize_to(390, 844)
    visit resources_path
    page.driver.browser.network_conditions = { latency: 1500, download_throughput: 50_000, upload_throughput: 50_000 }
    page.execute_script("window.__facetFetches = 0; document.addEventListener('turbo:before-fetch-request', () => window.__facetFetches += 1)")

    click_on "絞り込み"
    click_on "結果を見る"
    assert_selector ".results-panel[aria-busy='true']", visible: :all
    assert page.evaluate_script("document.querySelector('.mobile-result-action').disabled")
    assert_equal "反映中…", page.evaluate_script("document.querySelector('.mobile-result-action').textContent.trim()")

    page.execute_script("document.querySelector('#resource-filter-form').requestSubmit(document.querySelector('.mobile-result-action'))")
    assert_equal 1, page.evaluate_script("window.__facetFetches")

    assert_selector ".results-panel[aria-busy='false']", visible: :all
    assert_equal "results-heading", page.evaluate_script("document.activeElement.id")
  ensure
    page.driver.browser.delete_network_conditions
  end

  test "mobile header keeps login and readable theme controls" do
    page.current_window.resize_to(390, 844)
    visit resources_path

    assert_selector "header a", text: "ログイン", visible: true
    assert_selector "header select[aria-label='表示テーマ']", visible: true
    assert_operator page.evaluate_script("document.querySelector('header select[aria-label=\"表示テーマ\"]').getBoundingClientRect().height"), :>=, 44
  end

  private

  def focus_checkbox_by_tab(id, maximum_tabs: 80)
    maximum_tabs.times do
      break if page.evaluate_script("document.activeElement.id") == id

      page.send_keys(:tab)
    end

    assert_equal id, page.evaluate_script("document.activeElement.id")
  end

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
