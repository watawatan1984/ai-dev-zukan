module Admin
  class DashboardController < BaseController
    def index
      @review_pending_count = ResourceRevision.review_pending.count
      @summary_failed_count = ResourceRevision.summary_status_failed.count
      @published_count = Resource.published.count
      @recent_import_runs = ImportRun.order(started_at: :desc).limit(8)
      @recent_scheduled_executions = ScheduledExecution.order(scheduled_for: :desc).limit(8)
      @review_candidates = ResourceRevision.review_pending.includes(:resource).order(created_at: :asc).limit(10)
    end
  end
end
