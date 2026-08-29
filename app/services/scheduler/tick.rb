module Scheduler
  class Tick
    Result = Data.define(:status, :scheduled_for, :execution)
    ACTIVE_HOURS = (10..20)

    def self.call(now: Time.current)
      new(now:).call
    end

    def initialize(now:)
      @now = now.in_time_zone("Tokyo")
    end

    def call
      return Result.new(status: :outside_window, scheduled_for: nil, execution: nil) unless ACTIVE_HOURS.cover?(now.hour)

      scheduled_for = now.beginning_of_hour
      execution = ScheduledExecution.create!(task_name: "catalog_refresh", scheduled_for: scheduled_for)
      job = CatalogRefreshJob.perform_later(execution.id)
      execution.update!(status: :enqueued, active_job_id: job.job_id)
      Result.new(status: :enqueued, scheduled_for:, execution:)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      raise unless duplicate_execution?(error, scheduled_for)

      execution = ScheduledExecution.find_by!(task_name: "catalog_refresh", scheduled_for: scheduled_for)
      Result.new(status: :already_enqueued, scheduled_for:, execution:)
    end

    private

    attr_reader :now

    def duplicate_execution?(error, scheduled_for)
      return true if error.is_a?(ActiveRecord::RecordNotUnique)

      scheduled_for && error.record.errors.of_kind?(:task_name, :taken)
    end
  end
end
