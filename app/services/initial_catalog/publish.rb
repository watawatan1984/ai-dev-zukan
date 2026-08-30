module InitialCatalog
  class Publish
    ConfirmationRequired = Class.new(StandardError)
    ReviewerNotAuthorized = Class.new(StandardError)
    IncompleteCatalog = Class.new(StandardError)

    Result = Data.define(:target, :published_counts) do
      def complete?
        published_counts.values.all? { |count| count >= target }
      end
    end

    def self.call(reviewer:, confirmation:, limit: InitialCatalog::Bootstrap::MAX_LIMIT)
      new(reviewer:, confirmation:, limit:).call
    end

    def initialize(reviewer:, confirmation:, limit:)
      @reviewer = reviewer
      @confirmation = confirmation
      @limit = limit.to_i.clamp(1, InitialCatalog::Bootstrap::MAX_LIMIT)
    end

    def call
      raise ConfirmationRequired, "Set CONFIRM=publish to publish the initial catalog" unless confirmation == "publish"
      raise ReviewerNotAuthorized, "Only an admin can publish the initial catalog" unless reviewer&.admin?

      quality_report = InitialCatalog::QualityReport.call(target: limit)
      raise IncompleteCatalog, "Initial catalog quality gate failed" unless quality_report.acceptable?

      ensure_ready!
      Resource.transaction do
        kinds.each { |kind| publish_kind(kind) }
      end

      result = Result.new(target: limit, published_counts: published_counts)
      raise IncompleteCatalog, "Initial catalog publication is incomplete" unless result.complete?

      result
    end

    private

    attr_reader :reviewer, :confirmation, :limit

    def kinds
      InitialCatalog::Bootstrap::SOURCE_KINDS.values
    end

    def ensure_ready!
      shortages = kinds.filter_map do |kind|
        available = Resource.where(kind: kind).published.count + publishable_scope(kind).count
        "#{kind}=#{available}/#{limit}" if available < limit
      end
      return if shortages.empty?

      raise IncompleteCatalog, "Initial catalog is not ready: #{shortages.join(', ')}"
    end

    def publish_kind(kind)
      needed = limit - Resource.where(kind: kind).published.count
      return unless needed.positive?

      publishable_scope(kind)
        .order(Arel.sql("resources.popularity_score DESC"), :id)
        .limit(needed)
        .each do |revision|
          Editorial::ApproveAndPublish.call(
            revision:,
            reviewer:,
            request_id: "initial-catalog-bootstrap"
          )
        end
    end

    def publishable_scope(kind)
      InitialCatalog::LatestRevisions
        .for_kind(kind, publication_statuses: Resource.publication_statuses.fetch("unpublished"))
        .where(summary_status: :succeeded, review_status: :review_pending)
        .where.not(ai_summary: [ nil, "" ])
    end

    def published_counts
      kinds.index_with { |kind| Resource.where(kind: kind).published.count }.transform_keys(&:to_s)
    end
  end
end
