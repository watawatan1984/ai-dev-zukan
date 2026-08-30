module Taxonomy
  class SyncVocabulary
    def self.call
      new.call
    end

    def call
      ActiveRecord::Base.transaction do
        sync_categories
        sync_tags
      end
    end

    private

    def definition
      Taxonomy::Registry.definition
    end

    def sync_categories
      category_slugs = definition.fetch("categories").map { |category| category.fetch("slug") }

      definition.fetch("categories").each do |category_attributes|
        category = Category.find_or_initialize_by(slug: category_attributes.fetch("slug"))
        category.update!(
          name: category_attributes.fetch("name"),
          position: category_attributes.fetch("position"),
          active: category_attributes.fetch("active")
        )
      end

      Category.where.not(slug: category_slugs).update_all(active: false, updated_at: Time.current)
    end

    def sync_tags
      definition.fetch("tags").each do |tag_attributes|
        tag = Tag.find_or_initialize_by(slug: tag_attributes.fetch("slug"))
        tag.update!(
          name: tag_attributes.fetch("name"),
          normalized_name: tag_attributes.fetch("slug"),
          vocabulary_group: tag_attributes.fetch("group"),
          position: tag_attributes.fetch("position"),
          active: tag_attributes.fetch("active"),
          filterable: tag_attributes.fetch("filterable")
        )
        sync_aliases(tag, Array(tag_attributes.fetch("aliases")))
      end
    end

    def sync_aliases(tag, aliases)
      aliases.each do |alias_name|
        normalized_name = Taxonomy::Registry.normalize(alias_name)
        tag.tag_aliases.find_or_initialize_by(normalized_name: normalized_name).update!(name: alias_name)
      end
    end
  end
end
