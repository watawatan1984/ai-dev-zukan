class ResourcesController < ApplicationController
  def index
    search_params = params.permit(:q, :period, :sort, content_types: [], sources: [], category_slugs: [], tag_slugs: [])
    @selection = Search::Selection.build(params: search_params)
    results = Search::ResourcesQuery.call(selection: @selection, user: current_user)

    @result_count = results.count
    @facet_counts = Search::FacetCounts.call(selection: @selection, user: current_user, result_count: @result_count)
    @resources = results.limit(50).to_a
    @categories = Category.where(active: true).order(:position, :name).to_a
    @tags = Tag.where(slug: @facet_counts.fetch(:tags).keys).order(:vocabulary_group, :position, :name).to_a
    @bookmarked_ids = current_user ? current_user.bookmarks.where(resource: @resources).pluck(:resource_id).to_set : Set.new
  rescue Search::Selection::TooManyValues
    head :bad_request
  end

  def show
    @resource = Resource.publicly_visible.includes(:current_revision).find_by!(slug: params[:slug])
    @bookmarked = current_user&.bookmarks&.exists?(resource: @resource)
    @recommendations = Recommendations::RelatedResources.call(resource: @resource)
  end
end
