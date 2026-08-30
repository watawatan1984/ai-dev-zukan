module Editorial
  class ApproveAndPublish
    class ReviewerNotAuthorized < StandardError; end
    class RevisionNotReady < StandardError; end

    def self.call(revision:, reviewer:, request_id: nil)
      new(revision: revision, reviewer: reviewer, request_id: request_id).call
    end

    def initialize(revision:, reviewer:, request_id: nil)
      @revision = revision
      @reviewer = reviewer
      @request_id = request_id
    end

    def call
      raise ReviewerNotAuthorized, "Only an admin can approve revisions" unless reviewer.admin?
      unless revision.approved? || (revision.review_pending? && revision.ai_summary.present?)
        raise RevisionNotReady, "Revision must have a reviewed summary before publication"
      end

      revision.transaction do
        previous_status = revision.review_status
        before_controlled_category_ids = revision.resource.controlled_category_ids.sort
        before_controlled_tag_ids = revision.resource.controlled_tag_ids.sort
        validation = Taxonomy::ValidateSuggestion.call(revision: revision)
        raise Taxonomy::ApplyRevision::InvalidSuggestion, validation.errors unless validation.valid?

        unless revision.approved?
          revision.update!(
            review_status: :approved,
            reviewer: reviewer,
            reviewed_at: Time.current,
            rejection_reason: nil
          )
        end
        Taxonomy::ApplyRevision.call(revision: revision)
        revision.resource.publish!(revision: revision)
        resource = revision.resource.reload
        AdminAuditLog.create!(
          actor: reviewer,
          auditable: revision,
          action: "resource_revision.approve_and_publish",
          request_id: request_id,
          changeset: {
            review_status: [ previous_status, revision.review_status ],
            resource_id: revision.resource_id,
            controlled_category_ids: [ before_controlled_category_ids, resource.controlled_category_ids.sort ],
            controlled_tag_ids: [ before_controlled_tag_ids, resource.controlled_tag_ids.sort ]
          }
        )
      end

      revision.resource
    end

    private

    attr_reader :revision, :reviewer, :request_id
  end
end
