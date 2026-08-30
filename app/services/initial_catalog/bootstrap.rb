module InitialCatalog
  class Bootstrap
    SOURCE_KINDS = {
      "github_mcp" => :mcp,
      "github_skill" => :skill,
      "zenn" => :zenn_article,
      "qiita" => :qiita_article
    }.freeze
    MAX_ATTEMPTS = 3
    MAX_LIMIT = 100

    Result = Data.define(:target, :counts, :failures) do
      def complete?
        failures.empty? && counts.values.all? do |count|
          count.fetch(:resources) >= target && count.fetch(:summarized) >= target
        end
      end
    end

    def self.call(
      limit: MAX_LIMIT,
      catalogs: nil,
      summarizer_factory: -> { Ai::NvidiaSummarizer.new },
      concurrency: ENV.fetch("BOOTSTRAP_AI_CONCURRENCY", 3).to_i,
      import_sources: true,
      sleeper: ->(seconds) { sleep(seconds) },
      progress: ->(*) { }
    )
      new(
        limit:,
        catalogs:,
        summarizer_factory:,
        concurrency:,
        import_sources:,
        sleeper:,
        progress:
      ).call
    end

    def initialize(limit:, catalogs:, summarizer_factory:, concurrency:, import_sources:, sleeper:, progress:)
      @limit = limit.to_i.clamp(1, MAX_LIMIT)
      @catalogs = catalogs || default_catalogs
      @summarizer_factory = summarizer_factory
      @concurrency = concurrency.to_i.clamp(1, 4)
      @perform_import = import_sources
      @sleeper = sleeper
      @progress = progress
      @failures = {}
      @progress_count = 0
      @mutex = Mutex.new
    end

    def call
      import_sources if perform_import
      summarize_candidates
      Result.new(target: limit, counts: counts, failures: failures)
    end

    private

    attr_reader :limit, :catalogs, :summarizer_factory, :concurrency, :sleeper,
      :progress, :failures, :mutex, :perform_import

    def default_catalogs
      SOURCE_KINDS.keys.index_with { |source_name| Sources::Registry.catalog(source_name) }
    end

    def import_sources
      SOURCE_KINDS.each_key do |source_name|
        run = Ingestion::RefreshSource.call(
          source_name:,
          catalog: catalogs.fetch(source_name),
          limit:,
          enqueue_summaries: false
        )
        progress.call(
          event: "source_imported",
          source: source_name,
          fetched: run.fetched_count,
          created: run.created_count,
          unchanged: run.unchanged_count
        )
      end
    end

    def summarize_candidates
      revision_ids = candidate_revision_ids
      @candidate_total = revision_ids.length
      queue = Queue.new
      revision_ids.each { |revision_id| queue << revision_id }
      workers = [ concurrency, revision_ids.length ].min.times.map do
        Thread.new { summarize_queue(queue) }
      end
      workers.each(&:join)
    end

    def candidate_revision_ids
      SOURCE_KINDS.values.flat_map do |kind|
        needed = limit - summarized_count(kind)
        next [] unless needed.positive?

        InitialCatalog::LatestRevisions
          .for_kind(kind)
          .where(summary_status: [ :queued, :failed ])
          .where(review_status: [ :draft, :review_pending ])
          .order(:id)
          .limit(needed)
          .pluck(:id)
      end
    end

    def summarize_queue(queue)
      ActiveRecord::Base.connection_pool.with_connection do
        summarizer = summarizer_factory.call
        loop do
          revision_id = queue.pop(true)
          summarize_with_retries(revision_id, summarizer:)
        rescue ThreadError
          break
        end
      end
    end

    def summarize_with_retries(revision_id, summarizer:)
      attempts = 0
      begin
        attempts += 1
        revision = ResourceRevision.find(revision_id)
        Ai::GenerateSummary.call(revision:, summarizer:)
        record_progress(revision)
      rescue StandardError => error
        if attempts < MAX_ATTEMPTS
          sleeper.call(attempts)
          retry
        end
        mutex.synchronize { failures[revision_id] = "#{error.class}: #{error.message}" }
        progress.call(event: "summary_failed", revision_id:, error: error.class.name)
      end
    end

    def record_progress(revision)
      current_count = mutex.synchronize do
        @progress_count += 1
      end
      return unless (current_count % 10).zero? || current_count == @candidate_total

      progress.call(
        event: "summaries_progress",
        completed: current_count,
        kind: revision.resource.kind
      )
    end

    def counts
      SOURCE_KINDS.values.index_with do |kind|
        resource_scope = Resource.where(
          kind: kind,
          publication_status: InitialCatalog::LatestRevisions.active_publication_statuses
        )
        revision_scope = InitialCatalog::LatestRevisions.for_kind(kind)
        {
          resources: resource_scope.count,
          summarized: revision_scope.where(summary_status: :succeeded).distinct.count(:resource_id),
          review_pending: revision_scope.where(review_status: :review_pending).distinct.count(:resource_id),
          published: resource_scope.published.count
        }
      end.transform_keys(&:to_s)
    end

    def summarized_count(kind)
      InitialCatalog::LatestRevisions
        .for_kind(kind)
        .where(summary_status: :succeeded)
        .count
    end
  end
end
