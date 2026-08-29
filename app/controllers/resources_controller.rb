class ResourcesController < ApplicationController
  def index
    search_params = params.permit(:q, :kind, :category, :tag, :period, :sort)
    results = Search::ResourcesQuery.call(params: search_params, user: current_user)

    @result_count = results.count
    @resources = results.limit(50)
    @categories = Category.where(active: true).order(:position, :name)
    @tags = Tag.order(:name).limit(30)
    @bookmarked_ids = current_user ? current_user.bookmarks.where(resource: @resources).pluck(:resource_id).to_set : Set.new
  end

  def show
    @resource = Resource.publicly_visible.includes(:current_revision).find_by!(slug: params[:slug])
    @bookmarked = current_user&.bookmarks&.exists?(resource: @resource)
    @recommendations = Recommendations::RelatedResources.call(resource: @resource)
  end
end
