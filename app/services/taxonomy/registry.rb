require "digest"

module Taxonomy
  class Registry
    DefinitionError = Class.new(StandardError)

    class << self
      def version
        definition.fetch("version")
      end

      def definition
        @definition ||= load_definition
      end

      def categories
        Category.where(active: true).order(:position, :slug).map do |category|
          {
            "slug" => category.slug,
            "name" => category.name,
            "position" => category.position,
            "active" => category.active?
          }
        end
      end

      def tags
        Tag.where(active: true).includes(:tag_aliases).order(:vocabulary_group, :position, :slug).map do |tag|
          {
            "slug" => tag.slug,
            "name" => tag.name,
            "group" => tag.vocabulary_group,
            "position" => tag.position,
            "active" => tag.active?,
            "filterable" => tag.filterable?,
            "aliases" => tag.tag_aliases.sort_by(&:normalized_name).map(&:name)
          }
        end.sort_by { |tag| [ tag_group_position(tag.fetch("group")), tag.fetch("position"), tag.fetch("slug") ] }
      end

      def category_slugs
        definition.fetch("categories").map { |category| category.fetch("slug") }
      end

      def tag_slugs
        tags.map { |tag| tag.fetch("slug") }
      end

      def resolve_tag_slug(value)
        normalized = normalize(value)
        return if normalized.blank?

        Tag.where(active: true).find_by(slug: normalized)&.slug ||
          TagAlias.joins(:tag).merge(Tag.where(active: true)).find_by(normalized_name: normalized)&.tag&.slug
      end

      def prompt_payload
        {
          "version" => version,
          "categories" => categories,
          "tag_groups" => definition.fetch("tag_groups"),
          "tags" => tags
        }
      end

      def vocabulary_fingerprint
        Digest::SHA256.hexdigest(JSON.generate(prompt_payload))
      end

      def normalize(value)
        value.to_s.parameterize
      end

      private

      def tag_group_position(group)
        definition.fetch("tag_groups").keys.index(group) || definition.fetch("tag_groups").size
      end

      def load_definition
        raw = YAML.safe_load_file(Rails.root.join("config/taxonomy.yml"), aliases: false)
        validate_definition!(raw)
        raw
      end

      def validate_definition!(raw)
        raise DefinitionError, "taxonomy.yml must be a mapping" unless raw.is_a?(Hash)

        groups = raw.fetch("tag_groups")
        categories = raw.fetch("categories")
        tags = raw.fetch("tags")

        raise DefinitionError, "tag_groups must be a mapping" unless groups.is_a?(Hash)
        raise DefinitionError, "categories must be a list" unless categories.is_a?(Array)
        raise DefinitionError, "tags must be a list" unless tags.is_a?(Array)

        reject_duplicate!(categories.map { |category| category.fetch("slug") }, "category slug")
        tag_slugs = tags.map { |tag| tag.fetch("slug") }
        reject_duplicate!(tag_slugs, "tag slug")

        unknown_groups = tags.map { |tag| tag.fetch("group") }.uniq - groups.keys
        raise DefinitionError, "unknown tag groups: #{unknown_groups.join(', ')}" if unknown_groups.any?

        alias_targets = {}
        tags.each do |tag|
          Array(tag.fetch("aliases")).each do |alias_name|
            normalized = normalize(alias_name)
            raise DefinitionError, "blank alias for #{tag.fetch('slug')}" if normalized.blank?
            raise DefinitionError, "alias collides with canonical slug: #{alias_name}" if tag_slugs.include?(normalized)
            raise DefinitionError, "duplicate alias: #{alias_name}" if alias_targets.key?(normalized)

            alias_targets[normalized] = tag.fetch("slug")
          end
        end
      rescue KeyError => error
        raise DefinitionError, "missing taxonomy key: #{error.key}"
      end

      def reject_duplicate!(values, label)
        duplicates = values.group_by(&:itself).select { |_value, grouped| grouped.size > 1 }.keys
        raise DefinitionError, "duplicate #{label}: #{duplicates.join(', ')}" if duplicates.any?
      end
    end
  end
end
