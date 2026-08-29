class HiddenResourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_resource

  def create
    current_user.hidden_resources.find_or_create_by!(resource: @resource)
    redirect_to resources_path, notice: "検索結果から非表示にしました。"
  end

  def destroy
    current_user.hidden_resources.find_by(resource: @resource)&.destroy!
    redirect_back fallback_location: my_root_path, notice: "非表示を解除しました。"
  end

  private

  def set_resource
    @resource = Resource.publicly_visible.find_by!(slug: params[:resource_slug])
  end
end
