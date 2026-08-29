module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def google_oauth2
      user = Authentication::ResolveGoogleIdentity.call(
        auth: request.env.fetch("omniauth.auth"),
        signed_in_user: current_user
      )
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
      sign_in_and_redirect user, event: :authentication
    rescue Authentication::ResolveGoogleIdentity::UnverifiedEmail, ActiveRecord::RecordInvalid => error
      redirect_to new_user_session_path, alert: error.message
    end
  end
end
