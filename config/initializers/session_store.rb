Rails.application.config.session_store(
  :cookie_store,
  key: "_ai_dev_zukan_session",
  same_site: :lax,
  secure: Rails.env.production?,
  httponly: true
)
