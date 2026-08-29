module Search
  class ResourcesQuery
    ALLOWED_SORTS = %w[relevance popular newest].freeze
    PERIODS = {
      "7d" => 7.days,
      "30d" => 30.days,
      "1y" => 1.year
    }.freeze

    def self.call(params:, user: nil)
      new(params: params, user: user).call
    end

    def initialize(params:, user: nil)
      @params = params.to_h.with_indifferent_access
      @user = user
    end

    def call
      relation = Resource.publicly_visible.includes(:current_revision)
      relation = exclude_hidden(relation)
      relation = filter_kind(relation)
      relation = filter_category(relation)
      relation = filter_tag(relation)
      relation = filter_period(relation)
      relation = filter_query(relation)
      order(relation)
    end

    private

    attr_reader :params, :user

    def filter_kind(relation)
      return relation unless Resource.kinds.key?(params[:kind])

      relation.where(kind: params[:kind])
    end

    def filter_category(relation)
      return relation if params[:category].blank?

      relation.joins(:category).where(categories: { slug: params[:category] })
    end

    def filter_tag(relation)
      return relation if params[:tag].blank?

      relation.joins(:tags).where(tags: { slug: params[:tag] })
    end

    def filter_period(relation)
      duration = PERIODS[params[:period]]
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
      @normalized_query ||= Search::Normalize.call(params[:q])
    end

    def selected_sort
      ALLOWED_SORTS.include?(params[:sort]) ? params[:sort] : "relevance"
    end
  end
end
