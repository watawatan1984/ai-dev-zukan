class SourceImportJob < ApplicationJob
  queue_as :ingestion
  retry_on Sources::ProviderError, Faraday::TimeoutError, Faraday::ConnectionFailed, wait: 1.minute, attempts: 3

  def perform(source_name, limit: nil)
    Ingestion::RefreshSource.call(
      source_name:,
      catalog: Sources::Registry.catalog(source_name),
      limit: limit || ENV.fetch("SOURCE_IMPORT_LIMIT", 10).to_i
    )
  end
end
