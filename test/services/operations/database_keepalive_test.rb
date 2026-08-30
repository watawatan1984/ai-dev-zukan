require "test_helper"

class OperationsDatabaseKeepaliveTest < ActiveSupport::TestCase
  test "checks the database through a real SQL probe" do
    connection = RecordingConnection.new(1)
    checked_at = Time.zone.local(2026, 8, 30, 12, 0, 0)

    result = Operations::DatabaseKeepalive.call(connection:, now: checked_at)

    assert_equal [ "SELECT 1" ], connection.queries
    assert_equal :reachable, result.status
    assert_equal checked_at, result.checked_at
  end

  test "rejects an unexpected probe result" do
    connection = RecordingConnection.new(0)

    assert_raises Operations::DatabaseKeepalive::Unreachable do
      Operations::DatabaseKeepalive.call(connection:)
    end
  end

  class RecordingConnection
    attr_reader :queries

    def initialize(result)
      @result = result
      @queries = []
    end

    def select_value(sql)
      queries << sql
      @result
    end
  end
end
