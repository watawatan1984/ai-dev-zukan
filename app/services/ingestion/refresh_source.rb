module Ingestion
  class RefreshSource
    def self.call(
      source_name:,
      catalog:,
      limit: ENV.fetch("SOURCE_IMPORT_LIMIT", 10).to_i,
      enqueue_summaries: true
    )
      new(source_name:, catalog:, limit:, enqueue_summaries:).call
    end

    def initialize(source_name:, catalog:, limit:, enqueue_summaries:)
      @source_name = source_name
      @catalog = catalog
      @limit = limit.to_i.clamp(1, 100)
      @enqueue_summaries = enqueue_summaries
    end

    def call
      run = ImportRun.create!(source_name:, status: :running, started_at: Time.current)
      counts = Hash.new(0)
      snapshots = catalog.fetch(limit:)

      snapshots.each do |snapshot|
        result = Ingestion::UpsertSnapshot.call(snapshot:)
        counts[result.status] += 1
        enqueue_summary(result)
      end

      run.update!(
        status: :succeeded,
        fetched_count: snapshots.length,
        created_count: counts[:created_revision],
        unchanged_count: counts[:unchanged],
        completed_at: Time.current
      )
      run
    rescue StandardError => error
      run&.update!(status: :failed, error_message: error.message, completed_at: Time.current)
      raise
    end

    private

    attr_reader :source_name, :catalog, :limit, :enqueue_summaries

    def enqueue_summary(result)
      return unless enqueue_summaries
      return unless result.status == :created_revision
      return if result.revision.source_excerpt.blank?

      SummarizeRevisionJob.perform_later(result.revision.id)
    end
  end
end
