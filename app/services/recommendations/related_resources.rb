module Recommendations
  class RelatedResources
    Recommendation = Data.define(:resource, :score, :reasons)
    KIND_LABELS = {
      "mcp" => "MCP",
      "skill" => "Skill",
      "zenn_article" => "Zenn記事",
      "qiita_article" => "Qiita記事"
    }.freeze

    def self.call(resource:, limit: 4)
      new(resource:, limit:).call
    end

    def initialize(resource:, limit:)
      @resource = resource
      @limit = limit.to_i.clamp(1, 12)
    end

    def call
      candidates.filter_map { |candidate| recommendation_for(candidate) }
        .sort_by { |recommendation| [ -recommendation.score, -recommendation.resource.popularity_score.to_f ] }
        .first(limit)
    end

    private

    attr_reader :resource, :limit

    def candidates
      Resource.publicly_visible
        .where.not(id: resource.id)
        .includes(:current_revision, :category, :tags)
        .limit(100)
    end

    def recommendation_for(candidate)
      reasons = []
      score = 0.0

      if resource.category_id.present? && resource.category_id == candidate.category_id
        reasons << "#{resource.category.name}カテゴリが共通"
        score += 4
      end

      shared_tags = resource.tags.to_a & candidate.tags.to_a
      shared_tags.first(2).each { |tag| reasons << "#{tag.name}タグが共通" }
      score += shared_tags.length * 5

      if resource.kind == candidate.kind
        reasons << "同じ#{KIND_LABELS.fetch(resource.kind)}"
        score += 2
      end

      score += candidate.popularity_score.to_f
      return if reasons.empty?

      Recommendation.new(resource: candidate, score:, reasons:)
    end
  end
end
