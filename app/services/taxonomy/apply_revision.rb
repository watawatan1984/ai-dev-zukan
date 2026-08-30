module Taxonomy
  class ApplyRevision
    class InvalidSuggestion < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super(errors.join(", "))
      end
    end

    def self.call(revision:)
      new(revision:).call
    end

    def initialize(revision:)
      @revision = revision
    end

    def call
      validation = Taxonomy::ValidateSuggestion.call(revision:)
      raise InvalidSuggestion, validation.errors unless validation.valid?

      resource.transaction do
        replace_categories(validation.category_slugs)
        replace_tags(validation.tag_slugs)
      end

      resource
    end

    private

    attr_reader :revision

    delegate :resource, to: :revision

    def replace_categories(slugs)
      categories = Category.where(slug: slugs).index_by(&:slug)

      resource.resource_categories.delete_all
      slugs.each do |slug|
        resource.resource_categories.create!(
          category: categories.fetch(slug),
          origin: revision.taxonomy_origin
        )
      end
    end

    def replace_tags(slugs)
      tags = Tag.where(slug: slugs).index_by(&:slug)

      resource.controlled_resource_tags.delete_all
      slugs.each do |slug|
        resource.controlled_resource_tags.create!(
          tag: tags.fetch(slug),
          origin: revision.taxonomy_origin
        )
      end
    end
  end
end
