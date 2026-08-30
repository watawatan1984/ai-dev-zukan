class ClassifyRevisionJob < ApplicationJob
  queue_as :ai

  retry_on Faraday::TimeoutError, Faraday::ConnectionFailed, wait: 30.seconds, attempts: 3
  retry_on Ai::NvidiaTaxonomizer::ProviderError, wait: 30.seconds, attempts: 3

  def perform(revision_id)
    revision = ResourceRevision.find(revision_id)
    return unless revision.taxonomy_status_queued? || revision.taxonomy_status_failed?

    Taxonomy::GenerateSuggestion.call(revision:, taxonomizer: Ai::NvidiaTaxonomizer.new)
  end
end
