class BookmarksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_resource

  def create
    current_user.bookmarks.find_or_create_by!(resource: @resource)
    redirect_back fallback_location: resource_path(@resource.slug), notice: "気になるリストに追加しました。"
  end

  def destroy
    current_user.bookmarks.find_by(resource: @resource)&.destroy!
    redirect_back fallback_location: resource_path(@resource.slug), notice: "気になるリストから外しました。"
  end

  private

  def set_resource
    @resource = Resource.publicly_visible.find_by!(slug: params[:resource_slug])
  end
end
