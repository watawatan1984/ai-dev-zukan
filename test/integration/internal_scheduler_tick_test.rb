require "test_helper"

class InternalSchedulerTickTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  test "a signed GAS tick enqueues only one hourly catalog refresh" do
    with_scheduler_secret("test-scheduler-secret") do
      travel_to Time.zone.local(2026, 8, 30, 14, 23, 0) do
        headers = signed_headers(ENV.fetch("GAS_SCHEDULER_SECRET"))

        assert_enqueued_jobs 1, only: CatalogRefreshJob do
          post internal_scheduler_tick_path, params: "", headers: headers
          assert_response :accepted
          assert_equal "enqueued", response.parsed_body.fetch("status")

          post internal_scheduler_tick_path, params: "", headers: headers
          assert_response :success
          assert_equal "already_enqueued", response.parsed_body.fetch("status")
        end
      end
    end
  end

  test "an invalid signature is rejected" do
    with_scheduler_secret("test-scheduler-secret") do
      post internal_scheduler_tick_path,
        params: "",
        headers: {
          "X-Scheduler-Timestamp" => Time.current.to_i.to_s,
          "X-Scheduler-Signature" => "invalid"
        }

      assert_response :unauthorized
    end
  end

  private

  def signed_headers(secret)
    timestamp = Time.current.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.")
    {
      "X-Scheduler-Timestamp" => timestamp,
      "X-Scheduler-Signature" => signature
    }
  end

  def with_scheduler_secret(value)
    previous = ENV["GAS_SCHEDULER_SECRET"]
    ENV["GAS_SCHEDULER_SECRET"] = value
    yield
  ensure
    ENV["GAS_SCHEDULER_SECRET"] = previous
  end
end
