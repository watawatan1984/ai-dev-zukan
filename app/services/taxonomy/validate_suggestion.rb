module Taxonomy
  class ValidateSuggestion
    Result = Data.define(:category_slugs, :tag_slugs, :search_keywords, :errors) do
      def valid?
        errors.empty?
      end
    end

    def self.call(revision:)
      new(revision:).call
    end

    def initialize(revision:)
      @revision = revision
      @errors = []
    end

    def call
      category_slugs = validate_categories
      tag_slugs = validate_tags
      search_keywords = validate_search_keywords

      Result.new(category_slugs:, tag_slugs:, search_keywords:, errors:)
    end

    private

    attr_reader :revision, :errors

    def validate_categories
      slugs = Array(revision.effective_suggested_category_slugs).filter_map do |value|
        normalize_identifier(value).presence
      end

      validate_count(slugs, "category", 1..3)
      validate_duplicates(slugs, "category")

      active_slugs = Category.where(active: true, slug: slugs).pluck(:slug)
      slugs.each do |slug|
        errors << "unknown category: #{slug}" unless active_slugs.include?(slug)
      end

      slugs
    end

    def validate_tags
      raw_values = Array(revision.suggested_tag_slugs).filter_map do |value|
        normalize_identifier(value).presence
      end
      slugs = raw_values.map { |value| resolve_tag_slug(value) || value }

      validate_count(slugs, "tag", 2..6)
      validate_duplicates(slugs, "tag")
      validate_content_type_tags(slugs)

      active_slugs = Tag.where(active: true, slug: slugs).pluck(:slug)
      slugs.each do |slug|
        errors << "unknown tag: #{slug}" unless active_slugs.include?(slug)
      end

      slugs
    end

    def validate_search_keywords
      keywords = Array(revision.search_keywords).filter_map do |value|
        normalize_search_text(value).presence
      end

      errors << "too many search keywords: #{keywords.size}" if keywords.size > 30
      validate_duplicates(keywords, "search keyword")
      keywords.each do |keyword|
        errors << "search keyword too long: #{keyword}" if keyword.length > 80
      end

      keywords
    end

    def validate_count(slugs, label, range)
      return if range.cover?(slugs.size)

      errors << "#{label} count must be #{range.min}-#{range.max}: #{slugs.size}"
    end

    def validate_duplicates(values, label)
      values.tally.each_key do |value|
        errors << "duplicate #{label}: #{value}" if values.count(value) > 1
      end
    end

    def validate_content_type_tags(slugs)
      errors << "tag restates content type: mcp" if revision.resource.kind_mcp? && slugs.include?("mcp")
      errors << "tag restates content type: agent-skills" if revision.resource.kind_skill? && slugs.include?("agent-skills")
    end

    def resolve_tag_slug(value)
      Tag.where(active: true).find_by(slug: value)&.slug ||
        TagAlias.joins(:tag).merge(Tag.where(active: true)).find_by(normalized_name: Taxonomy::Registry.normalize(value))&.tag&.slug
    end

    def normalize_identifier(value)
      value.to_s.unicode_normalize(:nfkc).strip.downcase
    end

    def normalize_search_text(value)
      Search::Normalize.call(value)
    end
  end
end
