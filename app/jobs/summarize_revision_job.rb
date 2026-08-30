class SummarizeRevisionJob < ApplicationJob
  queue_as :ai

  retry_on Faraday::TimeoutError, Faraday::ConnectionFailed, wait: 30.seconds, attempts: 3
  retry_on Ai::NvidiaSummarizer::ProviderError, wait: 30.seconds, attempts: 3

  def perform(revision_id)
    revision = ResourceRevision.find(revision_id)
    return unless revision.summary_status_queued? || revision.summary_status_failed?

    Ai::GenerateSummary.call(revision:, summarizer: Ai::NvidiaSummarizer.new)
  end
end
