module ApplicationHelper
  require "uri"

  RESOURCE_KIND_LABELS = {
    "mcp" => "MCP",
    "skill" => "Skill",
    "zenn_article" => "Zenn",
    "qiita_article" => "Qiita"
  }.freeze

  SOURCE_PROVIDER_LABELS = {
    "github" => "GitHub",
    "zenn" => "Zenn",
    "qiita" => "Qiita",
    "manual" => "手動登録"
  }.freeze

  def resource_kind_label(resource)
    RESOURCE_KIND_LABELS.fetch(resource.kind, resource.kind.humanize)
  end

  def source_provider_label(resource)
    SOURCE_PROVIDER_LABELS.fetch(resource.source_provider, resource.source_provider.humanize)
  end

  def compact_number(value)
    number_to_human(value.to_i, units: { thousand: "K", million: "M" }, format: "%n%u", precision: 1)
  end

  def public_date(value)
    I18n.l(value.to_date, format: :long, locale: :ja)
  end

  def popularity_label(resource)
    label = case resource.source_provider
    when "github" then "GitHub Stars"
    when "zenn" then "Zenn いいね"
    when "qiita" then "Qiita いいね"
    else "人気"
    end

    "#{label} #{compact_number(resource.popularity_raw)}"
  end

  def safe_return_path(value)
    return resources_path unless value.is_a?(String) && value.present?

    uri = URI.parse(value)
    return resources_path unless uri.scheme.nil? && uri.host.nil? && uri.userinfo.nil?
    return resources_path unless uri.path == "/resources"

    value
  rescue URI::InvalidURIError
    resources_path
  end

  def google_oauth_configured?
    ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
  end
end
