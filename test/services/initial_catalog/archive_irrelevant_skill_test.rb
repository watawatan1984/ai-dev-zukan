require "test_helper"

class InitialCatalog::ArchiveIrrelevantSkillTest < ActiveSupport::TestCase
  FakeCatalog = Struct.new(:snapshots) do
    def fetch(limit:)
      snapshots.first(limit)
    end
  end

  test "archives adjacent apps while preserving explicit skill repositories" do
    adjacent = create_skill(title: "reactive-resume", excerpt: "An open source resume builder")
    skill = create_skill(title: "humanizer", excerpt: "A Claude Code skill")
    catalog = FakeCatalog.new([ snapshot_for(skill) ])

    result = InitialCatalog::ArchiveIrrelevantSkill.call(catalog:, limit: 1)

    assert_equal 1, result.selected_count
    assert_includes result.archived_ids, adjacent.id
    assert_predicate adjacent.reload, :archived?
    assert_predicate skill.reload, :unpublished?
  end

  private

  def create_skill(title:, excerpt:)
    uid = "example/#{title}"
    resource = Resource.create!(
      kind: :skill,
      slug: title,
      canonical_url: "https://github.com/#{uid}",
      normalized_canonical_url: "https://github.com/#{uid}",
      source_provider: :github,
      external_uid: uid
    )
    resource.revisions.create!(
      origin: :imported,
      title: title,
      source_excerpt: excerpt,
      source_fingerprint: "fingerprint-#{title}",
      ai_summary: "日本語の要約です。",
      summary_status: :succeeded,
      review_status: :review_pending
    )
    resource
  end


  def snapshot_for(resource)
    Sources::Snapshot.new(
      kind: :skill,
      provider: :github,
      external_uid: resource.external_uid,
      canonical_url: resource.canonical_url,
      title: resource.revisions.first.title,
      author_name: "example",
      excerpt: resource.revisions.first.source_excerpt,
      source_fingerprint: "selected",
      source_published_at: Time.current,
      source_updated_at: Time.current,
      popularity_raw: 1
    )
  end
end
