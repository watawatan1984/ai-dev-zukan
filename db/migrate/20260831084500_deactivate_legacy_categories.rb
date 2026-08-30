class DeactivateLegacyCategories < ActiveRecord::Migration[8.1]
  CONTROLLED_CATEGORY_SLUGS = %w[
    coding-development
    design-review
    testing-quality
    debugging-observability-performance
    research-search
    documentation-knowledge
    automation-integration
    data-databases
    infrastructure-devops
    security-governance
    ai-llm-agents
    design-content
    project-business-management
    learning-career
  ].freeze

  def up
    set_legacy_categories_active(false)
  end

  def down
    set_legacy_categories_active(true)
  end

  private

  def set_legacy_categories_active(active)
    quoted_slugs = CONTROLLED_CATEGORY_SLUGS.map { |slug| connection.quote(slug) }.join(", ")
    execute <<~SQL.squish
      UPDATE categories
      SET active = #{connection.quote(active)}, updated_at = CURRENT_TIMESTAMP
      WHERE slug NOT IN (#{quoted_slugs})
    SQL
  end
end
