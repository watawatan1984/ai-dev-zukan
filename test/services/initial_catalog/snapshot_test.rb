require "test_helper"
require "tempfile"

class InitialCatalog::SnapshotTest < ActiveSupport::TestCase
  test "exports a verified catalog and imports it idempotently without publishing" do
    InitialCatalog::Bootstrap::SOURCE_KINDS.values.each { |kind| create_summarized_resource(kind:) }

    Tempfile.create([ "initial-catalog", ".json" ]) do |file|
      exported = InitialCatalog::ExportSnapshot.call(path: file.path, target: 1)
      assert_equal InitialCatalog::Bootstrap::SOURCE_KINDS.values.index_with { 1 }.transform_keys(&:to_s), exported.counts

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
      suggested_tag_slugs: [ "agent" ],
      ai_provider: "nvidia",
      ai_model: "test-model",
      prompt_version: "v1",
      summary_basis: "source excerpt",
      summary_input_sha256: Digest::SHA256.hexdigest(uid),
      summary_generated_at: Time.current,
      summary_status: :succeeded,
      review_status: :review_pending
    )
  end
end
