module Sources
  module CanonicalUrl
    module_function

    def normalize(value)
      uri = URI.parse(value)
      raise ArgumentError, "Only HTTP(S) source URLs are supported" unless %w[http https].include?(uri.scheme)
      raise ArgumentError, "Source URL must include a host" if uri.host.blank?

      uri.scheme = uri.scheme.downcase
      uri.host = uri.host.downcase
      uri.query = nil
      uri.fragment = nil
      uri.path = uri.path.delete_suffix("/") unless uri.path == "/"
      uri.to_s
    rescue URI::InvalidURIError
      raise ArgumentError, "Source URL is invalid"
    end
  end
end
