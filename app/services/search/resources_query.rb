module Search
  class ResourcesQuery
    ALLOWED_SORTS = %w[relevance popular newest].freeze
    PERIODS = {
      "7d" => 7.days,
      "30d" => 30.days,
      "1y" => 1.year
    }.freeze

    def self.call(selection: nil, params: nil, user: nil)
      selection ||= Search::Selection.build(params: params || {})
      new(selection: selection, user: user).call
    end

    def self.relation(selection:, user: nil, except: nil)
      new(selection: selection, user: user, except: except).relation
    end

    def initialize(selection:, user: nil, except: nil)
      @selection = selection
      @user = user
      @except = Array(except).map(&:to_sym)
    end

    def call
      order(relation.includes(:current_revision))
    end

    def relation
      relation = Resource.publicly_visible
      relation = exclude_hidden(relation)
      relation = filter_content_type_and_source(relation)
      relation = filter_category(relation)
      relation = filter_tag(relation)
      relation = filter_period(relation)
      filter_query(relation)
    end

    private

    attr_reader :selection, :user, :except

    def filter_content_type_and_source(relation)
      relation = filter_content_type(relation) unless except.include?(:content_types)
      relation = filter_source(relation) unless except.include?(:sources)
      relation
    end

    def filter_content_type(relation)
      return relation if selection.content_types.empty?

      table = Resource.arel_table
      branches = []
      branches << table[:kind].eq(Resource.kinds.fetch("mcp")) if selection.content_types.include?("mcp")
      branches << table[:kind].eq(Resource.kinds.fetch("skill")) if selection.content_types.include?("skill")
      if selection.content_types.include?("blog")
        blog_branch = table[:kind].in([ Resource.kinds.fetch("zenn_article"), Resource.kinds.fetch("qiita_article") ])
        branches << blog_branch
      end

      relation.where(branches.reduce { |left, right| left.or(right) })
    end

    def filter_source(relation)
      return relation if selection.sources.empty? || !selection.content_types.include?("blog")

      table = Resource.arel_table
      non_blog_kinds = []
      non_blog_kinds << Resource.kinds.fetch("mcp") if selection.content_types.include?("mcp")
      non_blog_kinds << Resource.kinds.fetch("skill") if selection.content_types.include?("skill")
      source_values = selection.sources.map { |source| Resource.source_providers.fetch(source) }
      blog_branch = table[:kind].in([ Resource.kinds.fetch("zenn_article"), Resource.kinds.fetch("qiita_article") ])
        .and(table[:source_provider].in(source_values))

      predicate = non_blog_kinds.any? ? table[:kind].in(non_blog_kinds).or(blog_branch) : blog_branch
      relation.where(predicate)
    end

    def filter_category(relation)
      return relation if except.include?(:category_slugs)
      return relation if selection.category_slugs.empty?

      matching_ids = Resource.joins(:controlled_categories)
        .where(categories: { slug: selection.category_slugs })
        .select(:id)
      relation.where(id: matching_ids)
    end

    def filter_tag(relation)
      return relation if except.include?(:tag_slugs)
      return relation if selection.tag_slugs.empty?

      matching_ids = Resource.joins(:controlled_tags)
        .where(tags: { slug: selection.tag_slugs })
        .select(:id)
      relation.where(id: matching_ids)
    end

    def filter_period(relation)
      duration = PERIODS[selection.period]
      return relation unless duration

      relation.where(source_published_at: (Time.current - duration)..)
    end

    def exclude_hidden(relation)
      return relation unless user

      relation.where.not(id: user.hidden_resources.select(:resource_id))
    end

    def filter_query(relation)
      return relation if normalized_query.blank?

      contains = "%#{ActiveRecord::Base.sanitize_sql_like(normalized_query)}%"
      relation.where(
        "resources.search_text ILIKE :contains OR resources.search_text % :query",
        contains: contains,
        query: normalized_query
      )
    end

    def order(relation)
      case selected_sort
      when "popular"
        relation.order(popularity_score: :desc, published_at: :desc)
      when "newest"
        relation.order(published_at: :desc)
      else
        relevance_order(relation)
      end
    end

    def relevance_order(relation)
      return relation.order(published_at: :desc) if normalized_query.blank?

      quoted_query = ActiveRecord::Base.connection.quote(normalized_query)
      relation.order(
        Arel.sql("similarity(resources.search_text, #{quoted_query}) DESC, resources.published_at DESC")
      )
    end

    def normalized_query
      @normalized_query ||= Search::Normalize.call(selection.query)
    end

    def selected_sort
      ALLOWED_SORTS.include?(selection.sort) ? selection.sort : "relevance"
    end
  end
end
