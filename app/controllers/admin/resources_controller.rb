module Admin
  class ResourcesController < BaseController
    def index
      @resources = Resource.includes(:current_revision, :revisions).order(updated_at: :desc)
    end

    def new
    end

    def create
      revision = Editorial::CreateManualCandidate.call(
        attributes: resource_params,
        actor: current_user,
        request_id: request.request_id
      )
      SummarizeRevisionJob.perform_later(revision.id) if revision.summary_status_queued? && revision.source_excerpt.present?
      redirect_to admin_resource_revision_path(revision), notice: "レビュー候補を作成しました。"
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      flash.now[:alert] = error.message
      render :new, status: :unprocessable_content
    end

    private

    def resource_params
      params.expect(resource: [
        :kind,
        :title,
        :canonical_url,
        :author_name,
        :source_excerpt,
        :ai_summary
      ])
    end
  end
end
