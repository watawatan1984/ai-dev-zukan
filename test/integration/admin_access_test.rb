require "test_helper"

class AdminAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "regular user cannot open the admin dashboard" do
    user = User.create!(
      name: "Regular User",
      email: "user@example.com",
      password: "password123",
      role: :user,
      confirmed_at: Time.current
    )
    sign_in user

    get admin_root_path

    assert_redirected_to root_path
    assert_equal "管理者権限が必要です。", flash[:alert]
  end
end
