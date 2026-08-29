module Taxonomy
  class ApplyRevision
    def self.call(revision:)
      new(revision:).call
    end

    def initialize(revision:)
      @revision = revision
    end

    def call
      resource.category = resolved_category
      resource.save! if resource.changed?
      replace_ai_tags
      resource
    end

    private

    attr_reader :revision

    delegate :resource, to: :revision

    def resolved_category
      slug = normalize_slug(revision.suggested_category_slug)
      return if slug.blank?

      Category.find_or_create_by!(slug:) do |category|
        category.name = display_name(slug)
      end
    end

    def replace_ai_tags
      resource.resource_tags.origin_ai.delete_all
      normalized_tag_slugs.each do |slug|
        tag = Tag.find_or_create_by!(slug:) do |candidate|
          candidate.name = display_name(slug)
          candidate.normalized_name = slug
        end
        resource.resource_tags.find_or_create_by!(tag:) { |resource_tag| resource_tag.origin = :ai }
      end
    end

    def normalized_tag_slugs
      Array(revision.suggested_tag_slugs).filter_map do |value|
        normalize_slug(value).presence
      end.uniq.first(10)
    end

    def normalize_slug(value)
      value.to_s.parameterize.first(80)
    end

    def display_name(slug)
      slug.tr("-", " ").split.map(&:capitalize).join(" ")
    end
  end
end
