module Editorial
  class ApproveAndPublish
    class ReviewerNotAuthorized < StandardError; end

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

      revision.transaction do
        previous_status = revision.review_status
        revision.update!(
          review_status: :approved,
          reviewer: reviewer,
          reviewed_at: Time.current,
          rejection_reason: nil
        )
        revision.resource.publish!(revision: revision)
        AdminAuditLog.create!(
          actor: reviewer,
          auditable: revision,
          action: "resource_revision.approve_and_publish",
          request_id: request_id,
          changeset: {
            review_status: [ previous_status, revision.review_status ],
            resource_id: revision.resource_id
          }
        )
      end

      revision.resource
    end

    private

    attr_reader :revision, :reviewer, :request_id
  end
end
