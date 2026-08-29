module Authentication
  class ResolveGoogleIdentity
    class UnverifiedEmail < StandardError; end

    def self.call(auth:, signed_in_user: nil)
      new(auth: auth, signed_in_user: signed_in_user).call
    end

    def initialize(auth:, signed_in_user: nil)
      @auth = auth.to_h.deep_symbolize_keys
      @signed_in_user = signed_in_user
    end

    def call
      raise UnverifiedEmail, "Google account email is not verified" unless email_verified?

      existing_identity = OauthIdentity.find_by(provider: provider, uid: uid)
      return existing_identity.user if existing_identity

      User.transaction do
        user = signed_in_user || User.find_or_initialize_by(email: email)
        prepare_user(user)
        user.save!
        user.oauth_identities.create!(provider: provider, uid: uid, email: email)
        user
      end
    end

    private

    attr_reader :auth, :signed_in_user

    def prepare_user(user)
      user.name = auth.dig(:info, :name).presence || email.split("@").first if user.name.blank?
      user.password = Devise.friendly_token.first(32) if user.new_record?
      user.skip_confirmation! unless user.confirmed?
    end

    def email_verified?
      [ true, "true" ].include?(auth.dig(:extra, :id_info, :email_verified))
    end

    def provider
      auth.fetch(:provider)
    end

    def uid
      auth.fetch(:uid)
    end

    def email
      auth.dig(:info, :email).to_s.downcase
    end
  end
end
