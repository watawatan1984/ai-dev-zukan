require "test_helper"
require "tempfile"

class InitialCatalog::SnapshotTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
  end

  test "exports a verified catalog and imports it idempotently without publishing" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each { |kind| create_summarized_resource(kind:) }

    Tempfile.create([ "initial-catalog", ".json" ]) do |file|
      exported = InitialCatalog::ExportSnapshot.call(path: file.path, target: 1)
      assert_equal InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { 1 }.transform_keys(&:to_s), exported.counts
      payload = JSON.parse(File.read(file.path))
      assert_equal 2, payload.fetch("version")
      assert_equal Digest::SHA256.hexdigest(JSON.generate(payload.fetch("records"))), payload.fetch("records_sha256")
      assert_equal Digest::SHA256.hexdigest(JSON.generate(payload.fetch("taxonomy"))), payload.fetch("taxonomy_sha256")
      assert_equal Taxonomy::Registry.definition.fetch("categories").map { |category| category.fetch("slug") }, payload.fetch("taxonomy").fetch("categories").map { |category| category.fetch("slug") }
      assert_includes payload.fetch("taxonomy").fetch("tags").map { |tag| tag.fetch("slug") }, "ruby"
      assert_includes payload.fetch("taxonomy").fetch("tags").find { |tag| tag.fetch("slug") == "ruby-on-rails" }.fetch("aliases"), "rails"
      revision_payload = payload.fetch("records").first.fetch("revision")
      assert_equal [ "coding-development" ], revision_payload.fetch("suggested_category_slugs")
      assert_equal [ "ruby", "testing" ], revision_payload.fetch("suggested_tag_slugs")
      assert_equal [ "snapshot keyword" ], revision_payload.fetch("search_keywords")
      assert_equal "succeeded", revision_payload.fetch("taxonomy_status")
      assert_equal "ai", revision_payload.fetch("taxonomy_origin")
      assert_equal "catalog-taxonomy-v2", revision_payload.fetch("taxonomy_prompt_version")

      ResourceRevision.delete_all
      Resource.delete_all

      imported = InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)
      assert_equal 4, imported.created_revisions
      assert_equal 4, Resource.unpublished.count
      assert_equal 4, ResourceRevision.review_pending.count
      assert_equal 0, Resource.published.count

      assert_no_difference [ "Resource.count", "ResourceRevision.count" ] do
        second = InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)
        assert_equal 4, second.unchanged_revisions
      end
    end
  end

  test "imports v1 snapshots without publishing uncontrolled taxonomy" do
    payload = version_one_payload

    Tempfile.create([ "initial-catalog-v1", ".json" ]) do |file|
      write_snapshot(file.path, payload)

      imported = InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)
      assert_equal 4, imported.created_revisions

      mcp_revision = Resource.find_by!(kind: :mcp).revisions.sole
      assert_equal [ "coding-development" ], mcp_revision.suggested_category_slugs
      assert_equal [ "ruby-on-rails", "testing" ], mcp_revision.suggested_tag_slugs
      assert_predicate mcp_revision, :taxonomy_status_succeeded?

      skill_revision = Resource.find_by!(kind: :skill).revisions.sole
      assert_equal [], skill_revision.suggested_category_slugs
      assert_equal [], skill_revision.suggested_tag_slugs
      assert_equal "unknown-legacy-category", skill_revision.suggested_category_slug
      assert_predicate skill_revision, :taxonomy_status_queued?

      assert_equal 0, Resource.published.count
    end
  end

  test "queues v1 taxonomy when any original tag is uncontrolled" do
    payload = version_one_payload
    payload.fetch("records").first.fetch("revision")["suggested_tag_slugs"] = [ "rails", "testing", "uncontrolled-tag" ]

    Tempfile.create([ "initial-catalog-v1-partial-tags", ".json" ]) do |file|
      write_snapshot(file.path, payload)

      InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)

      revision = Resource.find_by!(kind: :mcp).revisions.sole
      assert_equal "coding-development", revision.suggested_category_slug
      assert_equal [], revision.suggested_category_slugs
      assert_equal [], revision.suggested_tag_slugs
      assert_predicate revision, :taxonomy_status_queued?
    end
  end

  test "queues v1 taxonomy when aliases resolve to duplicate canonical tags" do
    payload = version_one_payload
    payload.fetch("records").first.fetch("revision")["suggested_tag_slugs"] = [ "rails", "rubyonrails", "testing" ]

    Tempfile.create([ "initial-catalog-v1-duplicate-tags", ".json" ]) do |file|
      write_snapshot(file.path, payload)

      InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)

      revision = Resource.find_by!(kind: :mcp).revisions.sole
      assert_equal [], revision.suggested_category_slugs
      assert_equal [], revision.suggested_tag_slugs
      assert_predicate revision, :taxonomy_status_queued?
    end
  end

  test "imports v2 snapshots and recreates only declared active vocabulary" do
    payload = version_two_payload(
      taxonomy: {
        "version" => Taxonomy::Registry.version,
        "categories" => Taxonomy::Registry.definition.fetch("categories"),
        "tag_groups" => Taxonomy::Registry.definition.fetch("tag_groups"),
        "tags" => [
          {
            "slug" => "ruby",
            "name" => "Ruby",
            "group" => "language_framework",
            "position" => 10,
            "active" => true,
            "filterable" => true,
            "aliases" => []
          },
          {
            "slug" => "custom-admin-tag",
            "name" => "Custom Admin Tag",
            "group" => "technique_architecture",
            "position" => 20,
            "active" => true,
            "filterable" => false,
            "aliases" => [ "custom-admin-alias" ]
          }
        ]
      },
      category_slugs: [ "coding-development" ],
      tag_slugs: [ "ruby", "custom-admin-tag" ]
    )

    TagAlias.delete_all
    Tag.delete_all
    Category.delete_all

    Tempfile.create([ "initial-catalog-v2", ".json" ]) do |file|
      write_snapshot(file.path, payload)

      InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)

      assert_equal 14, Category.where(active: true).count
      assert_equal [ "custom-admin-tag", "ruby" ], Tag.where(active: true).order(:slug).pluck(:slug)
      assert_equal "custom-admin-tag", TagAlias.find_by!(normalized_name: "custom-admin-alias").tag.slug
      assert_nil Tag.find_by(slug: "python")
      assert_equal [ "ruby", "custom-admin-tag" ], Resource.find_by!(kind: :mcp).revisions.sole.suggested_tag_slugs
    end
  end

  test "rejects malformed v2 records before vocabulary sync or record import" do
    payload = version_two_payload
    payload.fetch("records").first.fetch("revision").delete("title")
    sentinel = Tag.create!(
      slug: "sentinel-tag",
      name: "Sentinel Tag",
      normalized_name: "sentinel-tag",
      vocabulary_group: "technique_architecture",
      active: true,
      filterable: true
    )

    Tempfile.create([ "initial-catalog-malformed-record", ".json" ]) do |file|
      write_snapshot(file.path, payload)

      error = assert_raises(InitialCatalog::ImportSnapshot::InvalidSnapshot) do
        InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)
      end

      assert_match(/missing revision key: title/, error.message)
      assert_predicate sentinel.reload, :active?
      assert_equal 0, Resource.count
      assert_equal 0, ResourceRevision.count
    end
  end

  test "rejects invalid v2 taxonomy before changing the database" do
    payload = version_two_payload(tag_slugs: [ "ruby", "missing-declared-tag" ])

    Tempfile.create([ "initial-catalog-invalid-taxonomy", ".json" ]) do |file|
      write_snapshot(file.path, payload)

      assert_no_difference [ "Resource.count", "ResourceRevision.count", "Tag.count", "Category.count", "TagAlias.count" ] do
        assert_raises(InitialCatalog::ImportSnapshot::InvalidSnapshot) do
          InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)
        end
      end
    end
  end

  test "rejects tampered v2 vocabulary before changing the database" do
    payload = version_two_payload
    payload.fetch("taxonomy").fetch("tags").first["name"] = "Tampered"

    Tempfile.create([ "initial-catalog-invalid-vocabulary", ".json" ]) do |file|
      File.write(file.path, JSON.generate(payload))

      assert_no_difference [ "Resource.count", "ResourceRevision.count", "Tag.count", "Category.count", "TagAlias.count" ] do
        assert_raises(InitialCatalog::ImportSnapshot::InvalidSnapshot) do
          InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)
        end
      end
    end
  end

  test "rejects malformed v2 aliases before vocabulary sync or record import" do
    [
      [ "nil alias", [ nil ] ],
      [ "blank alias", [ " " ] ],
      [ "duplicate normalized alias", [ "Rails", "rails" ] ],
      [ "tag slug collision", [ "testing" ] ]
    ].each do |label, aliases|
      payload = version_two_payload(taxonomy: taxonomy_with_ruby_aliases(aliases))
      sentinel = Tag.create!(
        slug: "sentinel-tag-#{label.parameterize}",
        name: "Sentinel #{label}",
        normalized_name: "sentinel-tag-#{label.parameterize}",
        vocabulary_group: "technique_architecture",
        active: true,
        filterable: true
      )

      Tempfile.create([ "initial-catalog-malformed-alias", ".json" ]) do |file|
        write_snapshot(file.path, payload)

        assert_raises(InitialCatalog::ImportSnapshot::InvalidSnapshot, label) do
          InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)
        end

        assert_predicate sentinel.reload, :active?, label
        assert_equal 0, Resource.count, label
        assert_equal 0, ResourceRevision.count, label
      end
    end
  end

  test "does not export v2 snapshots until every revision has publishable controlled taxonomy" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each do |kind|
      revision = create_summarized_resource(kind:)
      revision.update!(taxonomy_status: :queued) if kind == :mcp
    end

    Tempfile.create([ "initial-catalog-unready-taxonomy", ".json" ]) do |file|
      assert_raises(InitialCatalog::ExportSnapshot::InvalidCatalog) do
        InitialCatalog::ExportSnapshot.call(path: file.path, target: 1)
      end

      assert_equal "", File.read(file.path)
    end
  end

  test "rejects a modified snapshot before changing the database" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each { |kind| create_summarized_resource(kind:) }

    Tempfile.create([ "initial-catalog", ".json" ]) do |file|
      InitialCatalog::ExportSnapshot.call(path: file.path, target: 1)
      payload = JSON.parse(File.read(file.path))
      payload.fetch("records").first.fetch("revision")["ai_summary"] = "改ざん"
      File.write(file.path, JSON.generate(payload))

      assert_no_difference [ "Resource.count", "ResourceRevision.count" ] do
        assert_raises(InitialCatalog::ImportSnapshot::InvalidSnapshot) do
          InitialCatalog::ImportSnapshot.call(path: file.path, target: 1)
        end
      end
    end
  end

  private

  def create_summarized_resource(kind:)
    provider = kind.to_s.end_with?("article") ? kind.to_s.delete_suffix("_article") : "github"
    uid = "snapshot-#{kind}"
    resource = Resource.create!(
      kind:,
      slug: uid,
      canonical_url: "https://example.com/#{uid}",
      normalized_canonical_url: "https://example.com/#{uid}",
      source_provider: provider,
      external_uid: uid,
      popularity_raw: 10
    )
    resource.revisions.create!(
      origin: :imported,
      title: uid,
      author_name: "example",
      source_excerpt: "source excerpt",
      source_fingerprint: "fingerprint-#{uid}",
      ai_summary: "日本語の要約です。",
      capabilities: [ "機能" ],
      key_points: [ "要点" ],
      suggested_category_slug: "developer-tools",
      suggested_tag_slugs: [ "ruby", "testing" ],
      ai_provider: "nvidia",
      ai_model: "test-model",
      prompt_version: "v1",
      summary_basis: "source excerpt",
      summary_input_sha256: Digest::SHA256.hexdigest(uid),
      summary_generated_at: Time.zone.parse("2026-08-30 12:00:00"),
      summary_status: :succeeded,
      review_status: :review_pending,
      suggested_category_slugs: [ "coding-development" ],
      search_keywords: [ "snapshot keyword" ],
      taxonomy_status: :succeeded,
      taxonomy_origin: :ai,
      taxonomy_provider: "nvidia",
      taxonomy_model: "test-taxonomizer",
      taxonomy_prompt_version: "catalog-taxonomy-v2",
      taxonomy_input_sha256: Digest::SHA256.hexdigest("taxonomy-#{uid}"),
      taxonomy_generated_at: Time.zone.parse("2026-08-30 12:30:00"),
      taxonomy_confidence: 0.95
    )
  end

  def version_one_payload
    records = InitialCatalog::Bootstrap::SOURCE_KINDS.values.map.with_index do |kind, index|
      category_slug = index.zero? ? "coding-development" : "unknown-legacy-category"
      tag_slugs = index.zero? ? [ "rails", "testing" ] : [ "unknown-legacy-tag" ]
      snapshot_record(kind:, uid: "v1-#{kind}", revision: {
        "suggested_category_slug" => category_slug,
        "suggested_tag_slugs" => tag_slugs
      })
    end

    {
      "format" => InitialCatalog::ExportSnapshot::FORMAT,
      "version" => 1,
      "target" => 1,
      "counts" => InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { 1 }.transform_keys(&:to_s),
      "records_sha256" => Digest::SHA256.hexdigest(JSON.generate(records)),
      "records" => records
    }
  end

  def version_two_payload(taxonomy: default_taxonomy_payload, category_slugs: [ "coding-development" ], tag_slugs: [ "ruby", "testing" ])
    records = InitialCatalog::Bootstrap::SOURCE_KINDS.values.map do |kind|
      snapshot_record(kind:, uid: "v2-#{kind}", revision: {
        "suggested_category_slugs" => category_slugs,
        "suggested_tag_slugs" => tag_slugs,
        "search_keywords" => [ "portable snapshot" ],
        "taxonomy_status" => "succeeded",
        "taxonomy_origin" => "ai",
        "taxonomy_provider" => "nvidia",
        "taxonomy_model" => "test-taxonomizer",
        "taxonomy_prompt_version" => "catalog-taxonomy-v2",
        "taxonomy_input_sha256" => Digest::SHA256.hexdigest("taxonomy-v2-#{kind}"),
        "taxonomy_generated_at" => "2026-08-30T12:30:00.000000Z",
        "taxonomy_confidence" => 0.95
      })
    end

    {
      "format" => InitialCatalog::ExportSnapshot::FORMAT,
      "version" => 2,
      "target" => 1,
      "counts" => InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { 1 }.transform_keys(&:to_s),
      "records_sha256" => Digest::SHA256.hexdigest(JSON.generate(records)),
      "taxonomy_sha256" => Digest::SHA256.hexdigest(JSON.generate(taxonomy)),
      "taxonomy" => taxonomy,
      "records" => records
    }
  end

  def default_taxonomy_payload
    {
      "version" => Taxonomy::Registry.version,
      "categories" => Taxonomy::Registry.categories,
      "tag_groups" => Taxonomy::Registry.definition.fetch("tag_groups"),
      "tags" => Taxonomy::Registry.tags
    }
  end

  def taxonomy_with_ruby_aliases(aliases)
    default_taxonomy_payload.tap do |taxonomy|
      taxonomy.fetch("tags").find { |tag| tag.fetch("slug") == "ruby" }["aliases"] = aliases
    end
  end

  def snapshot_record(kind:, uid:, revision:)
    provider = kind.to_s.end_with?("article") ? kind.to_s.delete_suffix("_article") : "github"
    {
      "resource" => {
        "kind" => kind.to_s,
        "provider" => provider,
        "external_uid" => uid,
        "canonical_url" => "https://example.com/#{uid}",
        "source_published_at" => "2026-08-30T12:00:00.000000Z",
        "source_updated_at" => "2026-08-30T12:00:00.000000Z",
        "popularity_raw" => 10
      },
      "revision" => {
        "title" => uid,
        "author_name" => "example",
        "source_excerpt" => "source excerpt",
        "source_fingerprint" => "fingerprint-#{uid}",
        "ai_summary" => "日本語の要約です。",
        "capabilities" => [ "機能" ],
        "key_points" => [ "要点" ],
        "ai_provider" => "nvidia",
        "ai_model" => "test-model",
        "prompt_version" => "v1",
        "summary_basis" => "source excerpt",
        "summary_input_sha256" => Digest::SHA256.hexdigest(uid),
        "summary_generated_at" => "2026-08-30T12:00:00.000000Z"
      }.merge(revision)
    }
  end

  def write_snapshot(path, payload)
    payload["records_sha256"] = Digest::SHA256.hexdigest(JSON.generate(payload.fetch("records")))
    payload["taxonomy_sha256"] = Digest::SHA256.hexdigest(JSON.generate(payload.fetch("taxonomy"))) if payload["taxonomy"]
    File.write(path, JSON.generate(payload))
  end
end
