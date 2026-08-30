module AppHost
  module_function

  def resolve(environment = ENV)
    environment["APP_HOST"].presence ||
      environment["RENDER_EXTERNAL_HOSTNAME"].presence ||
      "localhost"
  end
end
