require "test_helper"

class Authentication::ResolveGoogleIdentityTest < ActiveSupport::TestCase
  test "verified Google identity creates a confirmed user" do
    auth = {
      provider: "google_oauth2",
      uid: "google-123",
      info: {
        email: "google-user@example.com",
        name: "Google User"
      },
      extra: {
        id_info: { email_verified: true }
      }
    }

    user = Authentication::ResolveGoogleIdentity.call(auth: auth)

    assert_equal "google-user@example.com", user.email
    assert_equal "Google User", user.name
    assert_predicate user, :confirmed?
    assert_equal "google-123", user.oauth_identities.first.uid
  end
end
