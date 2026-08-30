module InitialCatalog
  module LatestRevisions
    module_function

    def for_kind(kind, publication_statuses: active_publication_statuses)
      ResourceRevision
        .where(id: ResourceRevision.select("MAX(id)").group(:resource_id))
        .joins(:resource)
        .where(resources: {
          kind: Resource.kinds.fetch(kind.to_s),
          publication_status: publication_statuses
        })
    end

    def active_publication_statuses
      [ Resource.publication_statuses.fetch("unpublished"), Resource.publication_statuses.fetch("published") ]
    end
  end
end
