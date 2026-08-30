module Operations
  class DatabaseKeepalive
    Unreachable = Class.new(StandardError)
    Result = Data.define(:status, :checked_at)

    def self.call(connection: ActiveRecord::Base.connection, now: Time.current)
      probe = connection.select_value("SELECT 1")
      raise Unreachable, "Database keepalive probe returned an unexpected result" unless probe.to_i == 1

      Result.new(status: :reachable, checked_at: now)
    end
  end
end
