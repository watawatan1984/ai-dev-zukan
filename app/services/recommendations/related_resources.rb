module Recommendations
  class RelatedResources
    Recommendation = Data.define(:resource, :score, :reasons)
    KIND_LABELS = {
      "mcp" => "MCP",
      "skill" => "Skill",
      "zenn_article" => "Zenn記事",
      "qiita_article" => "Qiita記事"
    }.freeze

    def self.call(resource:, limit: 4, user: nil)
      new(resource:, limit:, user:).call
    end

    def initialize(resource:, limit:, user:)
      @resource = resource
      @limit = limit.to_i.clamp(1, 12)
      @user = user
    end

    def call
      candidates.filter_map { |candidate| recommendation_for(candidate) }
        .sort_by do |recommendation|
          recommended_resource = recommendation.resource
          [
            -recommendation.score,
            -recommended_resource.popularity_score.to_f,
            -(recommended_resource.published_at&.to_i || 0),
            recommended_resource.id
          ]
        end
        .first(limit)
    end

    private

    attr_reader :resource, :limit, :user

    def candidates
      scope = Resource.publicly_visible
        .where.not(id: resource.id)
        .includes(:current_revision, :controlled_categories, :controlled_tags)
        .limit(100)

      user ? scope.where.not(id: user.hidden_resources.select(:resource_id)) : scope
    end

    def recommendation_for(candidate)
      reasons = { categories: [], tags: [], kinds: [] }
      score = 0.0

      shared_categories(candidate).each do |category|
        reasons[:categories] << category.name
        score += 4
      end

      shared_tags(candidate).each do |tag|
        reasons[:tags] << tag.name
        score += 5
      end

      if resource.kind == candidate.kind
        reasons[:kinds] << "同じ#{KIND_LABELS.fetch(resource.kind)}"
        score += 2
      end

      reasons = reasons.compact_blank
      return if reasons.empty?

      Recommendation.new(resource: candidate, score:, reasons:)
    end

    def shared_categories(candidate)
      ordered_shared_records(
        source_records: resource.controlled_categories.to_a,
        candidate_records: candidate.controlled_categories.to_a,
        sort_attributes: [ :position, :name ]
      )
    end

    def shared_tags(candidate)
      ordered_shared_records(
        source_records: resource.controlled_tags.to_a,
        candidate_records: candidate.controlled_tags.to_a,
        sort_attributes: [ :vocabulary_group, :position, :name ]
      )
    end

    def ordered_shared_records(source_records:, candidate_records:, sort_attributes:)
      candidate_slugs = candidate_records.map(&:slug).to_set
      source_records
        .select { |record| candidate_slugs.include?(record.slug) }
        .sort_by { |record| sort_attributes.map { |attribute| record.public_send(attribute) } }
    end
  end
end
