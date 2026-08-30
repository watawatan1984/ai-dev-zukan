require "test_helper"

class InitialCatalog::ReleaseSnapshotTest < ActiveSupport::TestCase
  setup do
    Taxonomy::SyncVocabulary.call
    @snapshot_path = Rails.root.join("tmp/tests/initial_catalog_release_snapshot_#{SecureRandom.hex(8)}.json")
    FileUtils.mkdir_p(@snapshot_path.dirname)
  end

  teardown do
    FileUtils.rm_f(@snapshot_path)
  end

  test "switches existing published current revisions for every snapshot kind" do
    resources = InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with do |kind|
      create_published_resource_with_snapshot_candidate(kind:)
    end
    write_snapshot(resources:)

    result = InitialCatalog::ReleaseSnapshot.call(
      path: @snapshot_path,
      target: 1,
      reviewer: InitialCatalog::ReleaseReviewer.call,
      confirmation: InitialCatalog::ReleaseSnapshot::CONFIRMATION
    )

    assert result.complete?
    assert_equal InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { 1 }.transform_keys(&:to_s), result.current_counts
    resources.each_value do |resource|
      assert_equal "snapshot-#{resource.kind}", resource.reload.current_revision.source_fingerprint
      assert_equal "legacy-#{resource.kind}", resource.revisions.approved.where(source_fingerprint: "legacy-#{resource.kind}").sole.source_fingerprint
    end
  end

  test "requires distinct explicit confirmation" do
    resources = { mcp: create_published_resource_with_snapshot_candidate(kind: :mcp) }
    write_snapshot(resources:)

    assert_raises(InitialCatalog::ReleaseSnapshot::ConfirmationRequired) do
      InitialCatalog::ReleaseSnapshot.call(
        path: @snapshot_path,
        target: 1,
        reviewer: InitialCatalog::ReleaseReviewer.call,
        confirmation: "publish"
      )
    end
  end

  test "aborts without partial switches when a snapshot candidate is invalid" do
    resources = InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with do |kind|
      tag_slugs = kind == :qiita_article ? [ "ruby", "ruby" ] : [ "ruby", "testing" ]
      create_published_resource_with_snapshot_candidate(kind:, tag_slugs:)
    end
    original_current_ids = resources.transform_values(&:current_revision_id)
    write_snapshot(resources:)

    assert_raises(InitialCatalog::ReleaseSnapshot::InvalidRelease) do
      InitialCatalog::ReleaseSnapshot.call(
        path: @snapshot_path,
        target: 1,
        reviewer: InitialCatalog::ReleaseReviewer.call,
        confirmation: InitialCatalog::ReleaseSnapshot::CONFIRMATION
      )
    end

    resources.each do |kind, resource|
      assert_equal original_current_ids.fetch(kind), resource.reload.current_revision_id
      assert_predicate resource.revisions.find_by!(source_fingerprint: "snapshot-#{kind}"), :review_pending?
    end
  end

  test "requires existing resources to be published before update release" do
    resources = InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with do |kind|
      create_published_resource_with_snapshot_candidate(kind:)
    end
    resources.fetch(:skill).update!(publication_status: :unpublished)
    write_snapshot(resources:)

    assert_raises(InitialCatalog::ReleaseSnapshot::InvalidRelease) do
      InitialCatalog::ReleaseSnapshot.call(
        path: @snapshot_path,
        target: 1,
        reviewer: InitialCatalog::ReleaseReviewer.call,
        confirmation: InitialCatalog::ReleaseSnapshot::CONFIRMATION
      )
    end
  end

  test "rerun after success is a no-op with verified counts" do
    resources = InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with do |kind|
      create_published_resource_with_snapshot_candidate(kind:)
    end
    write_snapshot(resources:)
    reviewer = InitialCatalog::ReleaseReviewer.call

    first = InitialCatalog::ReleaseSnapshot.call(
      path: @snapshot_path,
      target: 1,
      reviewer:,
      confirmation: InitialCatalog::ReleaseSnapshot::CONFIRMATION
    )
    second = InitialCatalog::ReleaseSnapshot.call(
      path: @snapshot_path,
      target: 1,
      reviewer:,
      confirmation: InitialCatalog::ReleaseSnapshot::CONFIRMATION
    )

    assert_equal 4, first.switched_count
    assert_equal 0, second.switched_count
    assert second.complete?
    assert_equal 4, Resource.publicly_visible.count
  end

  private

  def create_published_resource_with_snapshot_candidate(kind:, tag_slugs: [ "ruby", "testing" ])
    identifier = kind.to_s
    provider = %i[mcp skill].include?(kind) ? :github : kind.to_s.delete_suffix("_article").to_sym
    resource = Resource.create!(
      kind:,
      slug: "release-#{identifier}",
      canonical_url: "https://example.com/#{identifier}",
      normalized_canonical_url: "https://example.com/#{identifier}",
      source_provider: provider,
      external_uid: "release-#{identifier}",
      publication_status: :unpublished,
      popularity_raw: 10,
      popularity_score: 0.1
    )
    legacy = resource.revisions.create!(
      origin: :imported,
      title: "Legacy #{identifier}",
      source_excerpt: "Legacy excerpt",
      source_fingerprint: "legacy-#{identifier}",
      ai_summary: "Legacy published summary.",
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: [ "ruby", "testing" ],
      search_keywords: [ "legacy" ],
      ai_provider: "fixture",
      ai_model: "fixture-model",
      prompt_version: "summary-v1",
      summary_basis: "fixture",
      summary_input_sha256: Digest::SHA256.hexdigest("legacy-#{identifier}"),
      summary_status: :succeeded,
      review_status: :review_pending,
      taxonomy_status: :succeeded,
      taxonomy_origin: :ai
    )
    Editorial::ApproveAndPublish.call(revision: legacy, reviewer: users(:admin), request_id: "test-legacy")
    resource.revisions.create!(
      origin: :imported,
      title: "Snapshot #{identifier}",
      source_excerpt: "Snapshot excerpt",
      source_fingerprint: "snapshot-#{identifier}",
      ai_summary: "Snapshot release summary.",
      capabilities: [ "Capability" ],
      key_points: [ "Point" ],
      suggested_category_slugs: [ "coding-development" ],
      suggested_tag_slugs: tag_slugs,
      search_keywords: [ "snapshot", identifier ],
      ai_provider: "fixture",
      ai_model: "fixture-model",
      prompt_version: "summary-v2",
      summary_basis: "fixture",
      summary_input_sha256: Digest::SHA256.hexdigest("snapshot-#{identifier}"),
      summary_generated_at: Time.current,
      summary_status: :succeeded,
      review_status: :review_pending,
      taxonomy_status: :succeeded,
      taxonomy_origin: :ai,
      taxonomy_provider: "fixture",
      taxonomy_model: "fixture-taxonomy",
      taxonomy_prompt_version: "taxonomy-v2.3",
      taxonomy_input_sha256: Digest::SHA256.hexdigest("taxonomy-#{identifier}"),
      taxonomy_generated_at: Time.current,
      taxonomy_confidence: 0.95
    )
    resource.reload
  end

  def write_snapshot(resources:)
    records = resources.values.map { |resource| snapshot_record(resource) }
    taxonomy = {
      "version" => Taxonomy::Registry.version,
      "categories" => Taxonomy::Registry.definition.fetch("categories"),
      "tag_groups" => Taxonomy::Registry.definition.fetch("tag_groups"),
      "tags" => Taxonomy::Registry.tags
    }
    payload = {
      "format" => InitialCatalog::ExportSnapshot::FORMAT,
      "version" => InitialCatalog::ExportSnapshot::VERSION,
      "target" => 1,
      "counts" => InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { 1 }.transform_keys(&:to_s),
      "records_sha256" => Digest::SHA256.hexdigest(JSON.generate(records)),
      "taxonomy_sha256" => Digest::SHA256.hexdigest(JSON.generate(taxonomy)),
      "taxonomy" => taxonomy,
      "records" => records
    }
    @snapshot_path.write(JSON.pretty_generate(payload))
  end

  def snapshot_record(resource)
    revision = resource.revisions.find_by!(source_fingerprint: "snapshot-#{resource.kind}")
    {
      "resource" => {
        "kind" => resource.kind,
        "provider" => resource.source_provider,
        "external_uid" => resource.external_uid,
        "canonical_url" => resource.canonical_url,
        "source_published_at" => resource.source_published_at&.iso8601(6),
        "source_updated_at" => resource.source_updated_at&.iso8601(6),
        "popularity_raw" => resource.popularity_raw
      },
      "revision" => {
        "title" => revision.title,
        "author_name" => revision.author_name,
        "source_excerpt" => revision.source_excerpt,
        "source_fingerprint" => revision.source_fingerprint,
        "ai_summary" => revision.ai_summary,
        "capabilities" => revision.capabilities,
        "key_points" => revision.key_points,
        "suggested_category_slug" => revision.suggested_category_slug,
        "suggested_category_slugs" => revision.suggested_category_slugs,
        "suggested_tag_slugs" => revision.suggested_tag_slugs,
        "search_keywords" => revision.search_keywords,
        "ai_provider" => revision.ai_provider,
        "ai_model" => revision.ai_model,
        "prompt_version" => revision.prompt_version,
        "summary_basis" => revision.summary_basis,
        "summary_input_sha256" => revision.summary_input_sha256,
        "summary_generated_at" => revision.summary_generated_at&.iso8601(6),
        "taxonomy_status" => revision.taxonomy_status,
        "taxonomy_origin" => revision.taxonomy_origin,
        "taxonomy_provider" => revision.taxonomy_provider,
        "taxonomy_model" => revision.taxonomy_model,
        "taxonomy_prompt_version" => revision.taxonomy_prompt_version,
        "taxonomy_input_sha256" => revision.taxonomy_input_sha256,
        "taxonomy_generated_at" => revision.taxonomy_generated_at&.iso8601(6),
        "taxonomy_confidence" => revision.taxonomy_confidence.to_f
      }
    }
  end
end
