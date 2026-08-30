module Taxonomy
  class EnqueueReclassification
    Result = Data.define(:resource_ids, :revision_ids)

    def self.call(scope: Resource.publicly_visible)
      new(scope:).call
    end

    def initialize(scope:)
      @scope = scope
      @resource_ids = []
      @revision_ids = []
    end

    def call
      scope.find_each { |resource| enqueue_resource(resource) }
      Result.new(resource_ids:, revision_ids:)
    end

    private

    attr_reader :scope, :resource_ids, :revision_ids

    def enqueue_resource(resource)
      candidate = Taxonomy::BuildReclassificationCandidate.call(resource:)
      return if candidate.taxonomy_status_succeeded? || candidate.taxonomy_status_processing?
      return if candidate.taxonomy_status_queued? && !candidate.previously_new_record?

      candidate.update!(taxonomy_status: :queued) if candidate.taxonomy_status_failed?
      ClassifyRevisionJob.perform_later(candidate.id)
      resource_ids << resource.id
      revision_ids << candidate.id
    end
  end
end
