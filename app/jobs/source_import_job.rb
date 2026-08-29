class SourceImportJob < ApplicationJob
  queue_as :ingestion
  retry_on Sources::ProviderError, Faraday::TimeoutError, Faraday::ConnectionFailed, wait: 1.minute, attempts: 3

  def perform(source_name)
    Ingestion::RefreshSource.call(
      source_name:,
      catalog: Sources::Registry.catalog(source_name)
    )
  end
end
