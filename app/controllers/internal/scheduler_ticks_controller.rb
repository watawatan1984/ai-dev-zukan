module Internal
  class SchedulerTicksController < ActionController::Base
    skip_forgery_protection

    def create
      unless Scheduler::VerifySignature.call(
        timestamp: request.headers["X-Scheduler-Timestamp"],
        signature: request.headers["X-Scheduler-Signature"],
        body: request.raw_post
      )
        return render json: { error: "invalid_signature" }, status: :unauthorized
      end

      result = Scheduler::Tick.call
      status = result.status == :enqueued ? :accepted : :ok
      render json: {
        status: result.status,
        scheduled_for: result.scheduled_for&.iso8601
      }, status: status
    end
  end
end
