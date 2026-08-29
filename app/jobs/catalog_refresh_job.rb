class CatalogRefreshJob < ApplicationJob
  queue_as :ingestion

  SOURCES = %w[github_mcp github_skill zenn qiita].freeze

  def perform(scheduled_execution_id)
    execution = ScheduledExecution.find(scheduled_execution_id)
    execution.update!(status: :running)
    SOURCES.each { |source| SourceImportJob.perform_later(source) }
    execution.update!(status: :succeeded, completed_at: Time.current)
  rescue StandardError => error
    execution&.update!(status: :failed, error_message: error.message, completed_at: Time.current)
    raise
  end
end
