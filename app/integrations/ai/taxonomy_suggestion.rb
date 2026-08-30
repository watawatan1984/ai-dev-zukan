module Ai
  TaxonomySuggestion = Data.define(
    :category_slugs,
    :tag_slugs,
    :search_keywords,
    :confidence,
    :provider,
    :model,
    :prompt_version
  )
end
