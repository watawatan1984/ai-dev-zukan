module My
  class DashboardController < ApplicationController
    before_action :authenticate_user!

    def index
      @bookmarked_resources = current_user.bookmarked_resources
        .merge(Resource.publicly_visible)
        .includes(:current_revision)
        .order("bookmarks.created_at DESC")
      @hidden_resources = current_user.hidden_resource_items
        .merge(Resource.publicly_visible)
        .includes(:current_revision)
        .order("hidden_resources.created_at DESC")
    end
  end
end
