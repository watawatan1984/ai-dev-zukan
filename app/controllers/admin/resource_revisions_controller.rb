module Admin
  class ResourceRevisionsController < BaseController
    before_action :set_revision

    def show
    end

    def edit
    end

    def update
      @revision.update!(revision_params.merge(review_status: :review_pending))
      redirect_to admin_resource_revision_path(@revision), notice: "候補版を更新しました。"
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_content
    end

    def approve_and_publish
      resource = Editorial::ApproveAndPublish.call(
        revision: @revision,
        reviewer: current_user,
        request_id: request.request_id
      )
      redirect_to resource_path(resource.slug), notice: "承認して公開しました。"
    end

    private

    def set_revision
      @revision = ResourceRevision.includes(:resource, :reviewer).find(params[:id])
    end

    def revision_params
      params.expect(resource_revision: [ :title, :author_name, :source_excerpt, :ai_summary ])
    end
  end
end
