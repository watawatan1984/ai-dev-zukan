require "test_helper"

class AdminTaxonomyWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    Taxonomy::SyncVocabulary.call
    @admin = users(:admin)
  end

  test "admin sees the fixed categories controlled tags aliases flags and usage counts" do
    sign_in @admin
    ruby = Tag.find_by!(slug: "ruby")
    create_published_resource(tag: ruby)

    get admin_taxonomy_path

    assert_response :success
    assert_select "[data-category-slug]", 14
    assert_select "[data-category-slug='coding-development']", text: /コード作成・開発支援/
    assert_select "[data-tag-slug='ruby']", text: /Ruby/
    assert_select "[data-tag-slug='ruby']", text: /language_framework/
    assert_select "[data-tag-slug='ruby']", text: /active/
    assert_select "[data-tag-slug='ruby']", text: /filterable/
    assert_select "[data-tag-slug='ruby'] [data-usage-count]", text: "1"
    assert_select "[data-tag-slug='ruby-on-rails']", text: /rails/
  end

  test "regular user receives the existing admin access response for taxonomy governance" do
    sign_in users(:regular)

    get admin_taxonomy_path

    assert_redirected_to root_path
    assert_equal "管理者権限が必要です。", flash[:alert]
  end

  test "admin creates a controlled tag with aliases and audit log" do
    sign_in @admin

    assert_difference [ "Tag.count", "TagAlias.count", "AdminAuditLog.count" ], 1 do
      post admin_tags_path, params: {
        tag: {
          slug: "solid-queue",
          name: "Solid Queue",
          vocabulary_group: "technique_architecture",
          aliases: "rails queue",
          active: "1",
          filterable: "1"
        }
      }
    end

    assert_redirected_to admin_taxonomy_path
    tag = Tag.find_by!(slug: "solid-queue")
    assert_predicate tag, :active?
    assert_predicate tag, :filterable?
    assert_equal "technique_architecture", tag.vocabulary_group
    assert_equal [ "rails queue" ], tag.tag_aliases.pluck(:name)
    assert_equal "solid-queue", Taxonomy::Registry.resolve_tag_slug("rails queue")
    audit_log = AdminAuditLog.find_by!(auditable: tag, action: "taxonomy.tag.create")
    assert_equal @admin, audit_log.actor
    assert_equal "solid-queue", audit_log.changeset.fetch("after").fetch("slug")
    assert_equal [ "rails queue" ], audit_log.changeset.fetch("after").fetch("aliases")
  end

  test "tag creation rejects unknown groups and rolls back aliases and audit" do
    sign_in @admin

    assert_no_difference [ "Tag.count", "TagAlias.count", "AdminAuditLog.count" ] do
      post admin_tags_path, params: {
        tag: {
          slug: "bad-group",
          name: "Bad Group",
          vocabulary_group: "not_a_group",
          aliases: "bad alias",
          active: "1",
          filterable: "0"
        }
      }
    end

    assert_response :unprocessable_content
    assert_match(/unknown tag group/, response.body)
  end

  test "admin merges tags by moving controlled joins aliases and auditing without touching legacy joins" do
    sign_in @admin
    destination = Tag.find_by!(slug: "ruby")
    source = Taxonomy::CreateTag.call(
      attributes: {
        slug: "ruby-worker",
        name: "Ruby Worker",
        vocabulary_group: "language_framework",
        aliases: [ "ruby jobs" ],
        active: true,
        filterable: true
      },
      actor: @admin,
      request_id: "setup-create"
    )
    moved_resource = create_published_resource(tag: source)
    duplicate_resource = create_published_resource(tag: source)
    duplicate_resource.controlled_resource_tags.create!(tag: destination, origin: :ai)
    legacy_resource = Resource.create!(
      kind: :skill,
      slug: "legacy-ruby-worker",
      canonical_url: "https://example.com/legacy-ruby-worker",
      normalized_canonical_url: "https://example.com/legacy-ruby-worker",
      source_provider: :manual
    )
    ResourceTag.create!(resource: legacy_resource, tag: source, origin: :source)

    assert_no_difference [ "Tag.count", "ResourceTag.count" ] do
      post merge_admin_tag_path(source), params: { destination_tag_id: destination.id }
    end

    assert_redirected_to admin_taxonomy_path
    assert_not source.reload.active?
    assert_not source.filterable?
    assert_equal [ destination.id ], moved_resource.reload.controlled_resource_tags.pluck(:tag_id)
    assert_equal [ destination.id ], duplicate_resource.reload.controlled_resource_tags.pluck(:tag_id)
    assert_equal [ source.id ], legacy_resource.resource_tags.pluck(:tag_id)
    assert_equal destination, TagAlias.find_by!(normalized_name: "ruby-jobs").tag
    assert_equal destination, TagAlias.find_by!(normalized_name: "ruby-worker").tag
    audit_log = AdminAuditLog.where(action: "taxonomy.tag.merge", auditable: destination).last
    assert_equal @admin, audit_log.actor
    assert_equal source.id, audit_log.changeset.fetch("source").fetch("id")
    assert_equal destination.id, audit_log.changeset.fetch("destination").fetch("id")
    assert_equal [ moved_resource.id, duplicate_resource.id ].sort, audit_log.changeset.fetch("moved_resource_ids").sort
    assert_equal false, audit_log.changeset.fetch("source_after").fetch("active")
  end

  test "tag merge rolls back when source and destination match" do
    sign_in @admin
    tag = Tag.find_by!(slug: "ruby")

    assert_no_difference "AdminAuditLog.count" do
      post merge_admin_tag_path(tag), params: { destination_tag_id: tag.id }
    end

    assert_response :unprocessable_content
    assert_predicate tag.reload, :active?
  end

  private

  def create_published_resource(tag:)
    resource = Resource.create!(
      kind: :zenn_article,
      slug: "taxonomy-resource-#{SecureRandom.hex(4)}",
      canonical_url: "https://example.com/#{SecureRandom.hex(8)}",
      normalized_canonical_url: "https://example.com/#{SecureRandom.hex(8)}",
      source_provider: :zenn,
      publication_status: :published,
      published_at: Time.current
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: "Published resource",
      source_fingerprint: SecureRandom.hex(16),
      ai_summary: "公開済みリソースです。",
      summary_status: :succeeded,
      review_status: :approved,
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ tag.slug, "testing" ],
      taxonomy_status: :succeeded
    )
    resource.update!(current_revision: revision)
    resource.controlled_resource_tags.create!(tag:, origin: :ai)
    resource
  end
end
