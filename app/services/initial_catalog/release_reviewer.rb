module InitialCatalog
  class ReleaseReviewer
    InvalidEmail = Class.new(StandardError)
    DEFAULT_EMAIL = "release-bot@ai-dev-zukan.invalid"

    def self.call(email: DEFAULT_EMAIL)
      new(email:).call
    end

    def initialize(email:)
      @email = email.to_s.downcase
    end

    def call
      raise InvalidEmail, "Release reviewer must use the reserved .invalid domain" unless email.end_with?(".invalid")

      User.transaction do
        reviewer = User.find_or_initialize_by(email:)
        reviewer.name = "Release Bot"
        reviewer.role = :admin
        reviewer.confirmed_at ||= Time.current
        reviewer.locked_at = Time.current
        set_initial_password(reviewer)
        reviewer.save!
        reviewer
      end
    end

    private

    attr_reader :email

    def set_initial_password(reviewer)
      return unless reviewer.new_record?

      password = SecureRandom.urlsafe_base64(48)
      reviewer.password = password
      reviewer.password_confirmation = password
    end
  end
end
