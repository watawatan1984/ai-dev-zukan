module Search
  class IndexText
    def self.call(resource:, revision:)
      new(resource:, revision:).call
    end

    def initialize(resource:, revision:)
      @resource = resource
      @revision = revision
    end

    def call
      Search::Normalize.call(values.flatten.compact.join(" "))
    end

    private

    attr_reader :resource, :revision

    def values
      [
        revision.title,
        revision.author_name,
        revision.ai_summary,
        revision.capabilities,
        revision.key_points,
        controlled_category_names,
        controlled_tag_terms,
        revision.search_keywords
      ]
    end

    def controlled_category_names
      resource.controlled_categories.order(:position, :slug).pluck(:name)
    end

    def controlled_tag_terms
      resource.controlled_tags.includes(:tag_aliases).order(:vocabulary_group, :position, :slug).flat_map do |tag|
        [ tag.name, tag.tag_aliases.map(&:name) ]
      end
    end
  end
end
