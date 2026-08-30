module Search
  class FacetCounts
    TAG_MINIMUM_USAGE = 3
    CONTENT_TYPES = %w[mcp skill blog].freeze
    SOURCES = %w[zenn qiita].freeze
    BLOG_KINDS = %w[zenn_article qiita_article].freeze

    def self.call(selection:, user: nil, result_count: nil)
      new(selection:, user:, result_count:).call
    end

    def initialize(selection:, user: nil, result_count: nil)
      @selection = selection
      @user = user
      @result_count = result_count
    end

    def call
      {
        content_types: content_type_counts,
        sources: source_counts,
        categories: category_counts,
        tags: tag_counts
      }
    end

    private

    attr_reader :selection, :user

    def content_type_counts
      counts = CONTENT_TYPES.index_with { 0 }
      base = relation(except: [ :content_types, :sources ])

      if selection.content_types.empty?
        add_kind_counts(counts, base.group(:kind).distinct.count(:id))
      else
        add_kind_counts(counts, content_type_extras(base).group(:kind).distinct.count(:id), starting_at: current_result_count)
      end

      counts
    end

    def source_counts
      counts = SOURCES.index_with { 0 }
      return counts unless selection.content_types.include?("blog")

      base = relation(except: :sources)
      if selection.sources.empty?
        grouped = base.where(kind: BLOG_KINDS.map { |kind| Resource.kinds.fetch(kind) })
          .group(:source_provider)
          .distinct
          .count(:id)
        non_blog_count = count_non_blog(base)
        add_source_counts(counts, grouped, starting_at: non_blog_count)
      else
        extras = outside_current(base)
          .where(kind: BLOG_KINDS.map { |kind| Resource.kinds.fetch(kind) })
          .group(:source_provider)
          .distinct
          .count(:id)
        add_source_counts(counts, extras, starting_at: current_result_count)
      end

      counts
    end

    def category_counts
      base = relation(except: :category_slugs)
      grouped = category_group_counts(selection.category_slugs.empty? ? base : outside_current(base))
      grouped.transform_values! { |count| count + current_result_count } if selection.category_slugs.any?
      grouped
    end

    def tag_counts
      base = relation(except: :tag_slugs)
      grouped = tag_group_counts(selection.tag_slugs.empty? ? base : outside_current(base))
      grouped.transform_values! { |count| count + current_result_count } if selection.tag_slugs.any?
      grouped
    end

    def relation(except: nil)
      Search::ResourcesQuery.relation(selection:, user:, except:)
    end

    def current_relation
      @current_relation ||= relation
    end

    def current_result_count
      @result_count ||= current_relation.distinct.count(:id)
    end

    def outside_current(base)
      base.where.not(id: current_relation.select(:id))
    end

    def add_kind_counts(counts, grouped, starting_at: 0)
      grouped.each do |kind_name, count|
        content_type = BLOG_KINDS.include?(kind_name) ? "blog" : kind_name
        counts[content_type] += count
      end
      counts.transform_values! { |count| count + starting_at }
    end

    def count_non_blog(base)
      selected_non_blog_kinds = selection.content_types & %w[mcp skill]
      return 0 if selected_non_blog_kinds.empty?

      base.where(kind: selected_non_blog_kinds.map { |kind| Resource.kinds.fetch(kind) }).distinct.count(:id)
    end

    def content_type_extras(base)
      extras = outside_current(base)
      return extras if selection.sources.empty?

      table = Resource.arel_table
      non_blog_branch = table[:kind].in(%w[mcp skill].map { |kind| Resource.kinds.fetch(kind) })
      blog_branch = table[:kind].in(BLOG_KINDS.map { |kind| Resource.kinds.fetch(kind) })
        .and(table[:source_provider].in(selection.sources.map { |source| Resource.source_providers.fetch(source) }))
      extras.where(non_blog_branch.or(blog_branch))
    end

    def add_source_counts(counts, grouped, starting_at: 0)
      grouped.each do |source_provider, count|
        counts[source_provider] += count if counts.key?(source_provider)
      end
      counts.transform_values! { |count| count + starting_at }
    end

    def category_group_counts(base)
      counted_join = "LEFT JOIN resource_categories counted_resource_categories " \
        "ON counted_resource_categories.category_id = categories.id " \
        "AND counted_resource_categories.resource_id IN (#{base.select(:id).to_sql})"

      Category.where(active: true)
        .joins(counted_join)
        .group("categories.id", "categories.slug")
        .order(:position, :name)
        .pluck("categories.slug", Arel.sql("COUNT(DISTINCT counted_resource_categories.resource_id)"))
        .to_h
    end

    def tag_group_counts(base)
      counted_join = "LEFT JOIN controlled_resource_tags counted_controlled_resource_tags " \
        "ON counted_controlled_resource_tags.tag_id = tags.id " \
        "AND counted_controlled_resource_tags.resource_id IN (#{base.select(:id).to_sql})"
      usage_join = "LEFT JOIN controlled_resource_tags usage_controlled_resource_tags " \
        "ON usage_controlled_resource_tags.tag_id = tags.id"

      Tag.where(active: true)
        .joins(counted_join)
        .joins(usage_join)
        .group("tags.id", "tags.slug")
        .having("tags.filterable = ? OR COUNT(DISTINCT usage_controlled_resource_tags.id) >= ?", true, TAG_MINIMUM_USAGE)
        .order(:vocabulary_group, :position, :name)
        .pluck("tags.slug", Arel.sql("COUNT(DISTINCT counted_controlled_resource_tags.resource_id)"))
        .to_h
    end
  end
end
