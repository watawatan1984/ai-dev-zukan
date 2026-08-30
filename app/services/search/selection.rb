module Search
  class Selection < Data.define(:query, :content_types, :sources, :category_slugs, :tag_slugs, :period, :sort)
    TooManyValues = Class.new(ArgumentError)

    MAXIMUMS = {
      content_types: 3,
      sources: 2,
      category_slugs: 14,
      tag_slugs: 20
    }.freeze

    CONTENT_TYPES = %w[mcp skill blog].freeze
    SOURCES = %w[zenn qiita].freeze
    SORTS = %w[relevance popular newest].freeze
    PERIODS = %w[7d 30d 1y].freeze

    class << self
      def build(params:)
        values = normalized_hash(params)
        content_types = ordered_values(values[:content_types], CONTENT_TYPES, :content_types)
        sources = ordered_values(values[:sources], SOURCES, :sources)
        sources = [] unless content_types.include?("blog")

        new(
          query: normalize_query(values[:q]),
          content_types: content_types,
          sources: sources,
          category_slugs: category_values(values[:category_slugs]),
          tag_slugs: tag_values(values[:tag_slugs]),
          period: PERIODS.include?(values[:period].to_s) ? values[:period].to_s : nil,
          sort: SORTS.include?(values[:sort].to_s) ? values[:sort].to_s : "relevance"
        )
      end

      private

      def normalized_hash(params)
        raw = if params.respond_to?(:to_unsafe_h)
          params.to_unsafe_h
        else
          params.to_h
        end
        raw.with_indifferent_access
      end

      def normalize_query(value)
        value.to_s.unicode_normalize(:nfkc).gsub(/\s+/, " ").strip.presence
      end

      def ordered_values(values, allowed_values, facet)
        normalized = array(values).map { |value| Taxonomy::Registry.normalize(value) }.uniq
        recognized = allowed_values & normalized
        raise_too_many!(facet, recognized.size) if recognized.size > MAXIMUMS.fetch(facet)

        recognized
      end

      def category_values(values)
        allowed_values = Taxonomy::Registry.category_slugs
        ordered_values(values, allowed_values, :category_slugs)
      end

      def tag_values(values)
        normalized = array(values).map { |value| Taxonomy::Registry.normalize(value) }.uniq
        resolved = normalized.filter_map { |value| Taxonomy::Registry.resolve_tag_slug(value) }.uniq
        recognized = Taxonomy::Registry.tag_slugs & resolved
        raise_too_many!(:tag_slugs, recognized.size) if recognized.size > MAXIMUMS.fetch(:tag_slugs)

        recognized
      end

      def array(values)
        Array.wrap(values).flat_map { |value| value.to_s.split(",") }.reject(&:blank?)
      end

      def raise_too_many!(facet, count)
        raise TooManyValues, "#{facet} accepts at most #{MAXIMUMS.fetch(facet)} values, received #{count}"
      end
    end

    def to_h
      {}.tap do |attributes|
        attributes[:q] = query if query.present?
        attributes[:content_types] = content_types if content_types.any?
        attributes[:sources] = sources if sources.any?
        attributes[:category_slugs] = category_slugs if category_slugs.any?
        attributes[:tag_slugs] = tag_slugs if tag_slugs.any?
        attributes[:period] = period if period.present?
        attributes[:sort] = sort if sort.present? && sort != "relevance"
      end
    end

    def to_query
      to_h.to_query
    end

    def filtered?
      query.present? ||
        content_types.any? ||
        sources.any? ||
        category_slugs.any? ||
        tag_slugs.any? ||
        period.present? ||
        (sort.present? && sort != "relevance")
    end

    def without(facet, value)
      case facet.to_sym
      when :q, :query
        return self unless query == self.class.send(:normalize_query, value)

        self.class.build(params: to_h.except(:q))
      when :period
        return self unless period == value.to_s

        self.class.build(params: to_h.except(:period))
      when :sort
        return self unless sort == value.to_s

        self.class.build(params: to_h.except(:sort))
      when :content_types
        self.class.build(params: to_h.merge(content_types: content_types - [ value.to_s ]))
      when :sources
        self.class.build(params: to_h.merge(sources: sources - [ value.to_s ]))
      when :category_slugs
        self.class.build(params: to_h.merge(category_slugs: category_slugs - [ value.to_s ]))
      when :tag_slugs
        self.class.build(params: to_h.merge(tag_slugs: tag_slugs - [ Taxonomy::Registry.resolve_tag_slug(value) ].compact))
      else
        self
      end
    end
  end
end
