module InitialCatalog
  class ArchiveIrrelevantSkill
    IncompleteSelection = Class.new(StandardError)
    Result = Data.define(:selected_count, :archived_ids, :reactivated_ids)

    def self.call(
      catalog: Sources::GithubCatalog.new(kind: :skill, readme_limit: 0),
      limit: InitialCatalog::Bootstrap::MAX_LIMIT
    )
      new(catalog:, limit:).call
    end

    def initialize(catalog:, limit:)
      @catalog = catalog
      @limit = limit.to_i.clamp(1, InitialCatalog::Bootstrap::MAX_LIMIT)
    end

    def call
      selected_uids = catalog.fetch(limit:).map(&:external_uid)
      if selected_uids.length < limit
        raise IncompleteSelection, "Skill selection returned #{selected_uids.length}/#{limit} resources"
      end

      reactivated_ids = reactivate_selected(selected_uids)
      archived_ids = []
      Resource.kind_skill.unpublished.find_each do |resource|
        next if selected_uids.include?(resource.external_uid)

        resource.update!(publication_status: :archived, archived_at: Time.current)
        archived_ids << resource.id
      end
      Result.new(selected_count: selected_uids.length, archived_ids:, reactivated_ids:)
    end

    private

    attr_reader :catalog, :limit

    def reactivate_selected(selected_uids)
      Resource.kind_skill.archived.where(external_uid: selected_uids).map do |resource|
        resource.update!(publication_status: :unpublished, archived_at: nil)
        resource.id
      end
    end
  end
end
