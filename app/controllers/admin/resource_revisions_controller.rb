module Admin
  class ResourceRevisionsController < BaseController
    before_action :set_revision

    def show
      @taxonomy_validation = Taxonomy::ValidateSuggestion.call(revision: @revision)
    end

    def edit
      set_taxonomy_options
    end

    def update
      attributes = revision_params
      attributes[:taxonomy_origin] = :admin if taxonomy_changed?(attributes)
      attributes[:taxonomy_status] = :succeeded if taxonomy_changed?(attributes)
      @revision.assign_attributes(attributes.merge(review_status: :review_pending))
      validation = Taxonomy::ValidateSuggestion.call(revision: @revision)
      unless validation.valid?
        @taxonomy_errors = validation.errors
        set_taxonomy_options
        return render :edit, status: :unprocessable_content
      end

      @revision.save!
      redirect_to admin_resource_revision_path(@revision), notice: "候補版を更新しました。"
    rescue ActiveRecord::RecordInvalid
      set_taxonomy_options
      render :edit, status: :unprocessable_content
    end

    def approve_and_publish
      resource = Editorial::ApproveAndPublish.call(
        revision: @revision,
        reviewer: current_user,
        request_id: request.request_id
      )
      redirect_to resource_path(resource.slug), notice: "承認して公開しました。"
    rescue Editorial::ApproveAndPublish::RevisionNotReady => error
      redirect_to admin_resource_revision_path(@revision), alert: error.message
    end

    private

    def set_revision
      @revision = ResourceRevision.includes(:resource, :reviewer).find(params[:id])
    end

    def revision_params
      permitted = params.require(:resource_revision).permit(
        :title,
        :author_name,
        :ai_summary,
        capabilities: [],
        key_points: [],
        suggested_category_slugs: [],
        suggested_tag_slugs: [],
        search_keywords: []
      )
      %i[suggested_category_slugs suggested_tag_slugs].each do |key|
        permitted[key] = compact_values(permitted[key])
      end
      %i[capabilities key_points search_keywords].each do |key|
        permitted[key] = compact_values(permitted[key]).flat_map { |value| value.split(/\r?\n/) }.filter_map(&:presence)
      end
      permitted.to_h.with_indifferent_access
    end

    def taxonomy_changed?(attributes)
      return true if attributes.key?(:suggested_category_slugs) && attributes.fetch(:suggested_category_slugs) != @revision.suggested_category_slugs
      return true if attributes.key?(:suggested_tag_slugs) && attributes.fetch(:suggested_tag_slugs) != @revision.suggested_tag_slugs

      false
    end

    def compact_values(values)
      Array(values).filter_map { |value| value.to_s.strip.presence }
    end

    def set_taxonomy_options
      @category_options = Taxonomy::Registry.categories
      @tag_options = Taxonomy::Registry.tags
    end
  end
end
