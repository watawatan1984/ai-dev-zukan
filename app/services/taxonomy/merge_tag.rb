module Taxonomy
  class MergeTag
    InvalidMerge = Class.new(StandardError)

    def self.call(source:, destination:, actor:, request_id: nil)
      new(source:, destination:, actor:, request_id:).call
    end

    def initialize(source:, destination:, actor:, request_id: nil)
      @source = source
      @destination = destination
      @actor = actor
      @request_id = request_id
    end

    def call
      raise InvalidMerge, "Only an admin can merge tags" unless actor.admin?
      raise InvalidMerge, "source and destination must differ" if source.id == destination.id
      raise InvalidMerge, "destination tag must be active" unless destination.active?

      Tag.transaction do
        source_before = serialize(source)
        destination_before = serialize(destination)
        moved_resource_ids = move_controlled_joins
        move_aliases
        add_destination_alias(source.name)
        add_destination_alias(source.slug)
        source.update!(active: false, filterable: false)
        AdminAuditLog.create!(
          actor:,
          auditable: destination,
          action: "taxonomy.tag.merge",
          request_id:,
          changeset: {
            source: { id: source.id, slug: source_before.fetch(:slug) },
            destination: { id: destination.id, slug: destination_before.fetch(:slug) },
            moved_resource_ids: moved_resource_ids.sort,
            source_before:,
            source_after: serialize(source.reload),
            destination_before:,
            destination_after: serialize(destination.reload)
          }
        )
        destination
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      raise InvalidMerge, error.message
    end

    private

    attr_reader :source, :destination, :actor, :request_id

    def move_controlled_joins
      moved_resource_ids = []
      source.controlled_resource_tags.find_each do |join|
        moved_resource_ids << join.resource_id
        if ControlledResourceTag.exists?(resource_id: join.resource_id, tag_id: destination.id)
          join.destroy!
        else
          join.update!(tag: destination)
        end
      end
      moved_resource_ids
    end

    def move_aliases
      source.tag_aliases.find_each do |tag_alias|
        existing = TagAlias.where(normalized_name: tag_alias.normalized_name).where.not(id: tag_alias.id).first
        next if existing && existing.tag_id != destination.id

        existing&.destroy!
        tag_alias.update!(tag: destination)
      end
    end

    def add_destination_alias(value)
      normalized = Taxonomy::Registry.normalize(value)
      return if normalized.blank? || normalized == destination.slug

      existing = TagAlias.find_by(normalized_name: normalized)
      return if existing&.tag_id == destination.id
      return if existing

      destination.tag_aliases.create!(name: value.to_s.strip, normalized_name: normalized)
    end

    def serialize(tag)
      tag.reload
      {
        id: tag.id,
        slug: tag.slug,
        name: tag.name,
        group: tag.vocabulary_group,
        active: tag.active?,
        filterable: tag.filterable?,
        aliases: tag.tag_aliases.order(:normalized_name).pluck(:name)
      }
    end
  end
end
