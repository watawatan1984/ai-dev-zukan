module Ai
  Summary = Data.define(
    :summary,
    :capabilities,
    :key_points,
    :suggested_category_slug,
    :suggested_tag_slugs,
    :provider,
    :model,
    :prompt_version,
    :basis
  ) do
    def initialize(**attributes)
      super
      raise ArgumentError, "summary is required" if summary.blank?
    end
  end
end
