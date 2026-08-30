module Taxonomy
  class CreateTag
    InvalidTag = Class.new(StandardError)

    def self.call(attributes:, actor:, request_id: nil)
      new(attributes:, actor:, request_id:).call
    end

    def initialize(attributes:, actor:, request_id: nil)
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
      @request_id = request_id
    end

    def call
      raise InvalidTag, "Only an admin can create tags" unless actor.admin?

      Tag.transaction do
        validate!
        tag = Tag.create!(
          slug: slug,
          name: name,
          normalized_name: normalized_name,
          vocabulary_group: group,
          position: position,
          active: active?,
          filterable: filterable?
        )
        aliases.each do |alias_name|
          tag.tag_aliases.create!(
            name: alias_name,
            normalized_name: Taxonomy::Registry.normalize(alias_name)
          )
        end
        AdminAuditLog.create!(
          actor:,
          auditable: tag,
          action: "taxonomy.tag.create",
          request_id:,
          changeset: {
            before: nil,
            after: serialize(tag.reload)
          }
        )
        tag
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      raise InvalidTag, error.message
    end

    private

    attr_reader :attributes, :actor, :request_id

    def validate!
      raise InvalidTag, "slug is required" if slug.blank?
      raise InvalidTag, "name is required" if name.blank?
      raise InvalidTag, "unknown tag group: #{group}" unless allowed_groups.include?(group)
      raise InvalidTag, "duplicate tag slug: #{slug}" if Tag.exists?(slug:)
      raise InvalidTag, "duplicate tag name: #{name}" if Tag.exists?(normalized_name:)

      aliases.each do |alias_name|
        normalized_alias = Taxonomy::Registry.normalize(alias_name)
        raise InvalidTag, "blank alias" if normalized_alias.blank?
        raise InvalidTag, "alias collides with canonical slug: #{alias_name}" if Tag.exists?(slug: normalized_alias)
        raise InvalidTag, "duplicate alias: #{alias_name}" if TagAlias.exists?(normalized_name: normalized_alias)
      end

      duplicated_alias = aliases.map { |alias_name| Taxonomy::Registry.normalize(alias_name) }
        .tally
        .find { |_alias_name, count| count > 1 }
      raise InvalidTag, "duplicate alias: #{duplicated_alias.first}" if duplicated_alias
    end

    def allowed_groups
      Taxonomy::Registry.definition.fetch("tag_groups").keys
    end

    def slug
      @slug ||= Taxonomy::Registry.normalize(attributes[:slug])
    end

    def name
      @name ||= attributes[:name].to_s.strip
    end

    def normalized_name
      @normalized_name ||= Taxonomy::Registry.normalize(name)
    end

    def group
      @group ||= attributes[:vocabulary_group].to_s
    end

    def aliases
      @aliases ||= begin
        values = attributes[:aliases]
        values = values.to_s.split(/[,\n]/) unless values.is_a?(Array)
        values.filter_map { |value| value.to_s.strip.presence }
      end
    end

    def active?
      ActiveModel::Type::Boolean.new.cast(attributes.fetch(:active, true))
    end

    def filterable?
      ActiveModel::Type::Boolean.new.cast(attributes.fetch(:filterable, false))
    end

    def position
      @position ||= Tag.where(vocabulary_group: group).maximum(:position).to_i + 10
    end

    def serialize(tag)
      {
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
