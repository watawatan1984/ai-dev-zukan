require "test_helper"

class InitialCatalog::ReleaseReviewerTest < ActiveSupport::TestCase
  test "creates an idempotent locked system admin on the reserved invalid domain" do
    reviewer = InitialCatalog::ReleaseReviewer.call
    repeated = InitialCatalog::ReleaseReviewer.call

    assert_equal reviewer.id, repeated.id
    assert_equal "release-bot@ai-dev-zukan.invalid", reviewer.email
    assert_predicate reviewer, :admin?
    assert_predicate reviewer, :confirmed?
    assert_predicate reviewer, :access_locked?
    refute_predicate reviewer, :active_for_authentication?
  end

  test "rejects a release reviewer address outside the reserved invalid domain" do
    assert_raises(InitialCatalog::ReleaseReviewer::InvalidEmail) do
      InitialCatalog::ReleaseReviewer.call(email: "admin@example.com")
    end
  end

  test "renews an expired timed lock before a release" do
    reviewer = InitialCatalog::ReleaseReviewer.call
    reviewer.update!(locked_at: User.unlock_in.ago - 1.minute)

    refute_predicate reviewer.reload, :access_locked?

    renewed = InitialCatalog::ReleaseReviewer.call

    assert_predicate renewed, :access_locked?
    refute_predicate renewed, :active_for_authentication?
  end
end
