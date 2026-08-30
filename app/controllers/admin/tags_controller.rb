module Admin
  class TagsController < BaseController
    def create
      Taxonomy::CreateTag.call(
        attributes: tag_params,
        actor: current_user,
        request_id: request.request_id
      )
      redirect_to admin_taxonomy_path, notice: "タグを追加しました。"
    rescue Taxonomy::CreateTag::InvalidTag => error
      render_taxonomy(error.message)
    end

    def merge
      Taxonomy::MergeTag.call(
        source: Tag.find(params[:id]),
        destination: Tag.find(params[:destination_tag_id]),
        actor: current_user,
        request_id: request.request_id
      )
      redirect_to admin_taxonomy_path, notice: "タグを統合しました。"
    rescue ActiveRecord::RecordNotFound, Taxonomy::MergeTag::InvalidMerge => error
      render_taxonomy(error.message)
    end

    private

    def tag_params
      params.require(:tag).permit(:slug, :name, :vocabulary_group, :aliases, :active, :filterable).to_h
    end

    def render_taxonomy(message)
      @categories = Taxonomy::Registry.categories
      @tags = Tag.where(active: true).includes(:tag_aliases).order(:vocabulary_group, :position, :slug)
      @usage_counts = ControlledResourceTag.joins(:resource).merge(Resource.publicly_visible).group(:tag_id).count
      flash.now[:alert] = message
      render "admin/taxonomy/index", status: :unprocessable_content
    end
  end
end
