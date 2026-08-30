require "test_helper"

class LegalPagesTest < ActionDispatch::IntegrationTest
  test "privacy policy is public and canonical" do
    get privacy_path

    assert_response :success
    assert_select "h1", "プライバシーポリシー"
    assert_select "link[rel='canonical'][href='#{privacy_url}']"
  end

  test "terms are public and linked from the footer" do
    get terms_path

    assert_response :success
    assert_select "h1", "利用規約"
    assert_select "footer a[href='#{privacy_path}']"
    assert_select "footer a[href='#{terms_path}']"
  end
end
