require "test_helper"

class AuthenticationPagesTest < ActionDispatch::IntegrationTest
  test "registration page collects the required display name" do
    get new_user_registration_path

    assert_response :success
    assert_select "input[name='user[name]']"
    assert_select "input[name='user[email]']"
  end

  test "login page is available from the public navigation" do
    get new_user_session_path

    assert_response :success
    assert_select "form[action='#{user_session_path}']"
  end
end
