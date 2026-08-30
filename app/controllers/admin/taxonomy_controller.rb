module Admin
  class TaxonomyController < BaseController
    def index
      @categories = Taxonomy::Registry.categories
      @tags = Tag.where(active: true)
        .includes(:tag_aliases)
        .order(:vocabulary_group, :position, :slug)
      @usage_counts = usage_counts
    end

    private

    def usage_counts
      ControlledResourceTag
        .joins(:resource)
        .merge(Resource.publicly_visible)
        .group(:tag_id)
        .count
    end
  end
end
