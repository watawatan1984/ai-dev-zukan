require "test_helper"

class Taxonomy::ReclassificationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Taxonomy::SyncVocabulary.call
    clear_enqueued_jobs
  end

  test "builds an immutable taxonomy v2 candidate from the current approved revision" do
    resource = create_published_resource(kind: :mcp, slug: "immutable-candidate")
    approved_revision = resource.current_revision
    approved_attributes = approved_revision.reload.attributes

    candidate = Taxonomy::BuildReclassificationCandidate.call(resource:)

    assert_equal approved_revision.ai_summary, candidate.ai_summary
    assert_equal approved_revision.summary_basis, candidate.summary_basis
    assert_equal approved_revision.summary_input_sha256, candidate.summary_input_sha256
    assert_equal approved_revision.ai_provider, candidate.ai_provider
    assert_equal approved_revision.ai_model, candidate.ai_model
    assert_equal approved_revision.prompt_version, candidate.prompt_version
    assert_predicate candidate, :draft?
    assert_predicate candidate, :summary_status_succeeded?
    assert_predicate candidate, :taxonomy_status_queued?
    assert_equal Digest::SHA256.hexdigest("#{approved_revision.source_fingerprint}:taxonomy-v2"), candidate.source_fingerprint
    assert_nil candidate.reviewer
    assert_nil candidate.reviewed_at
    assert_nil candidate.rejection_reason
    assert_equal approved_attributes, approved_revision.reload.attributes
  end

  test "enqueueing reclassification is idempotent for eligible published resources" do
    resource = create_published_resource(kind: :skill, slug: "idempotent-enqueue")

    first = Taxonomy::EnqueueReclassification.call(scope: Resource.where(id: resource.id))
    second = Taxonomy::EnqueueReclassification.call(scope: Resource.where(id: resource.id))

    assert_equal [ resource.id ], first.resource_ids
    assert_empty second.resource_ids
    assert_equal 1, resource.revisions.where(
      source_fingerprint: Digest::SHA256.hexdigest("#{resource.current_revision.source_fingerprint}:taxonomy-v2")
    ).count
    assert_equal 1, enqueued_jobs.count { |job| job.fetch(:job) == ClassifyRevisionJob }
  end

  test "exports deterministic base sample and appends required review records" do
    resources = []
    Resource.kinds.keys.each do |kind|
      21.times do |index|
        resources << create_published_resource(kind: kind.to_sym, slug: "export-#{kind}-#{index}")
      end
    end
    candidates = resources.index_with do |resource|
      create_candidate_for(resource)
    end
    failed = create_candidate_for(create_published_resource(kind: :mcp, slug: "export-required-failed"), taxonomy_status: :failed)
    low_confidence = create_candidate_for(create_published_resource(kind: :skill, slug: "export-required-low"), confidence: 0.70)
    invalid = create_candidate_for(
      create_published_resource(kind: :zenn_article, slug: "export-required-invalid"),
      categories: [ "unknown-category" ],
      tags: [ "ruby", "testing" ]
    )
    scoped_resources = resources + [ failed.resource, low_confidence.resource, invalid.resource ]
    expected_base_ids = Resource.kinds.keys.flat_map do |kind|
      scoped_resources
        .select { |resource| resource.kind == kind }
        .sort_by { |resource| Digest::SHA256.hexdigest("taxonomy-v2:#{resource.id}") }
        .first(20)
        .map(&:id)
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      result = Taxonomy::ExportReviewSample.call(scope: Resource.where(id: scoped_resources.map(&:id)), path:)
      payload = JSON.parse(File.read(path))

      assert_equal path, result.path
      assert_equal "ai-dev-zukan.taxonomy-review", payload.fetch("format")
      assert_equal "taxonomy-v2", payload.fetch("taxonomy_version")
      assert_equal expected_base_ids, payload.fetch("records").first(80).map { |record| record.fetch("resource_id") }
      assert_equal 20, payload.fetch("records").first(80).count { |record| record.fetch("kind") == "mcp" }
      assert_includes payload.fetch("records").select { |record| record.fetch("required_review") }.map { |record| record.fetch("resource_id") }, failed.resource_id
      assert_includes payload.fetch("records").select { |record| record.fetch("required_review") }.map { |record| record.fetch("resource_id") }, low_confidence.resource_id
      assert_includes payload.fetch("records").select { |record| record.fetch("required_review") }.map { |record| record.fetch("resource_id") }, invalid.resource_id
      assert_equal Digest::SHA256.hexdigest(JSON.generate(payload.fetch("records"))), payload.fetch("records_sha256")
      assert candidates.values.all?(&:taxonomy_status_succeeded?)
    end
  end

  test "quality report rejects substituted missing extra and duplicate artifact records with recomputed checksums" do
    resources = Resource.kinds.keys.map do |kind|
      create_published_resource(kind: kind.to_sym, slug: "artifact-identity-#{kind}")
    end
    resources.each { |resource| create_candidate_for(resource) }

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      Taxonomy::ExportReviewSample.call(scope: Resource.where(id: resources.map(&:id)), path:, base_sample_per_kind: 1)
      original_records = with_review_decisions(JSON.parse(File.read(path)).fetch("records"))

      {
        "missing artifact record ids" => original_records.drop(1),
        "extra artifact record ids" => original_records + [ original_records.first.merge("resource_id" => 999_999) ],
        "duplicate artifact record ids" => original_records + [ original_records.first ],
        "substituted artifact record ids" => original_records.drop(1) + [ original_records.first.merge("resource_id" => 999_998) ]
      }.each do |expected_error, records|
        write_review(path, records)

        report = Taxonomy::QualityReport.call(scope: Resource.where(id: resources.map(&:id)), review_path: path, target_per_kind: 1, base_sample_per_kind: 1)

        refute report.acceptable?, expected_error
        assert_includes report.errors, expected_error
      end
    end
  end

  test "quality report rejects nil decisions on ordinary base rows" do
    resource = create_published_resource(kind: :mcp, slug: "nil-base-decision")
    create_candidate_for(resource)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      Taxonomy::ExportReviewSample.call(scope: Resource.where(id: resource.id), path:, base_sample_per_kind: 1)
      records = JSON.parse(File.read(path)).fetch("records")
      records.first["category_match"] = nil
      records.first["tag_match"] = true
      write_review(path, records)

      report = Taxonomy::QualityReport.call(scope: Resource.where(id: resource.id), review_path: path, target_per_kind: 0, base_sample_per_kind: 1)

      refute report.acceptable?
      assert_includes report.errors, "resource #{resource.id} category_match must be boolean"
    end
  end

  test "quality report rejects non decision artifact data tampering with a recomputed checksum" do
    resource = create_published_resource(kind: :mcp, slug: "tampered-canonical-data")
    create_candidate_for(resource)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      Taxonomy::ExportReviewSample.call(scope: Resource.where(id: resource.id), path:, base_sample_per_kind: 1)
      records = with_review_decisions(JSON.parse(File.read(path)).fetch("records"))
      records.first["title"] = "Tampered title"
      write_review(path, records)

      report = Taxonomy::QualityReport.call(scope: Resource.where(id: resource.id), review_path: path, target_per_kind: 0, base_sample_per_kind: 1)

      refute report.acceptable?
      assert_includes report.errors, "resource #{resource.id} title does not match current candidate"
    end
  end

  test "low confidence base candidate exports once as required review and remains in base accuracy" do
    resource = create_published_resource(kind: :skill, slug: "low-confidence-base")
    create_candidate_for(resource, confidence: 0.70)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      Taxonomy::ExportReviewSample.call(scope: Resource.where(id: resource.id), path:, base_sample_per_kind: 1)
      records = JSON.parse(File.read(path)).fetch("records")

      assert_equal [ resource.id ], records.map { |record| record.fetch("resource_id") }
      assert_equal true, records.first.fetch("required_review")

      records.first["category_match"] = false
      records.first["tag_match"] = true
      write_review(path, records)

      report = Taxonomy::QualityReport.call(scope: Resource.where(id: resource.id), review_path: path, target_per_kind: 0, base_sample_per_kind: 1)

      refute report.acceptable?
      assert_equal 0.0, report.category_accuracy
      assert_equal 1.0, report.tag_accuracy
      assert_includes report.errors, "category accuracy below 90%: 0.0%"
    end
  end

  test "quality report rejects omitted or falsely unmarked low confidence required review candidates" do
    low_resource = create_published_resource(kind: :zenn_article, slug: "low-confidence-required")
    create_candidate_for(low_resource, confidence: 0.70)
    ordinary_resource = create_published_resource(kind: :zenn_article, slug: "ordinary-required-sibling")
    create_candidate_for(ordinary_resource)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      Taxonomy::ExportReviewSample.call(scope: Resource.where(id: [ low_resource.id, ordinary_resource.id ]), path:, base_sample_per_kind: 1)
      exported = with_review_decisions(JSON.parse(File.read(path)).fetch("records"))
      low_record = exported.find { |record| record.fetch("resource_id") == low_resource.id }

      write_review(path, exported.reject { |record| record.fetch("resource_id") == low_resource.id })
      omitted = Taxonomy::QualityReport.call(scope: Resource.where(id: [ low_resource.id, ordinary_resource.id ]), review_path: path, target_per_kind: 0, base_sample_per_kind: 1)

      refute omitted.acceptable?
      assert_includes omitted.errors, "missing artifact record ids"

      low_record["required_review"] = false
      write_review(path, [ low_record ])
      unmarked = Taxonomy::QualityReport.call(scope: Resource.where(id: [ low_resource.id, ordinary_resource.id ]), review_path: path, target_per_kind: 0, base_sample_per_kind: 1)

      refute unmarked.acceptable?
      assert_includes unmarked.errors, "resource #{low_resource.id} required_review must be true"
    end
  end

  test "quality report rejects low review accuracy and incomplete required reviews" do
    resources = [
      create_published_resource(kind: :mcp, slug: "quality-good"),
      create_published_resource(kind: :skill, slug: "quality-bad"),
      create_published_resource(kind: :zenn_article, slug: "quality-required")
    ]
    resources.each { |resource| create_candidate_for(resource) }
    required_resource = resources.last
    required_resource.revisions.last.update!(taxonomy_confidence: 0.70)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      Taxonomy::ExportReviewSample.call(scope: Resource.where(id: resources.map(&:id)), path:, base_sample_per_kind: 1)
      payload = JSON.parse(File.read(path))
      payload.fetch("records").each do |record|
        record["category_match"] = record.fetch("resource_id") != resources.second.id
        record["tag_match"] = true
      end
      required_record = payload.fetch("records").find { |record| record.fetch("resource_id") == required_resource.id && record.fetch("required_review") }
      required_record["category_match"] = nil
      File.write(path, JSON.pretty_generate(payload))

      report = Taxonomy::QualityReport.call(scope: Resource.where(id: resources.map(&:id)), review_path: path, target_per_kind: 1)

      refute report.acceptable?
      assert_includes report.errors, "required review incomplete for resource #{required_resource.id}"
      assert_operator report.category_accuracy, :<, 0.90
    end
  end

  test "quality report enforces launch scope counts and valid succeeded taxonomy candidates" do
    resource = create_published_resource(kind: :qiita_article, slug: "quality-invalid-candidate")
    candidate = create_candidate_for(resource, tags: [ "ruby", "ruby" ])

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      write_review(path, [ review_record_for(candidate, category_match: true, tag_match: true) ])

      report = Taxonomy::QualityReport.call(scope: Resource.where(id: resource.id), review_path: path)

      refute report.acceptable?
      assert_includes report.errors, "qiita_article has 1 taxonomy-v2 candidates; expected at least 100"
      assert_includes report.errors, "resource #{resource.id} taxonomy invalid: duplicate tag: ruby"
    end
  end

  test "publish requires exact confirmation and locked system admin reviewer" do
    resource = create_published_resource(kind: :mcp, slug: "publish-confirmation")
    candidate = create_candidate_for(resource, review_status: :review_pending)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      write_review(path, [ review_record_for(candidate, category_match: true, tag_match: true) ])

      assert_raises(Taxonomy::PublishReclassification::ConfirmationRequired) do
        Taxonomy::PublishReclassification.call(reviewer: users(:admin), confirmation: "publish", review_path: path, scope: Resource.where(id: resource.id), target_per_kind: 1)
      end
      assert_raises(Taxonomy::PublishReclassification::ReviewerNotAuthorized) do
        Taxonomy::PublishReclassification.call(reviewer: users(:regular), confirmation: "publish-taxonomy-v2", review_path: path, scope: Resource.where(id: resource.id), target_per_kind: 1)
      end
      assert_raises(Taxonomy::PublishReclassification::ReviewerNotAuthorized) do
        Taxonomy::PublishReclassification.call(reviewer: users(:admin), confirmation: "publish-taxonomy-v2", review_path: path, scope: Resource.where(id: resource.id), target_per_kind: 1)
      end
    end
  end

  test "publish validates all candidates before the first write and leaves no partial publication" do
    reviewer = InitialCatalog::ReleaseReviewer.call
    valid_resource = create_published_resource(kind: :mcp, slug: "publish-valid")
    invalid_resource = create_published_resource(kind: :skill, slug: "publish-invalid")
    valid_candidate = create_candidate_for(valid_resource, review_status: :review_pending)
    invalid_candidate = create_candidate_for(invalid_resource, review_status: :review_pending, tags: [ "ruby", "ruby" ])
    original_current_ids = [ valid_resource, invalid_resource ].index_with { |resource| resource.current_revision_id }

    Dir.mktmpdir do |dir|
      path = File.join(dir, "review.json")
      write_review(path, [
        review_record_for(valid_candidate, category_match: true, tag_match: true),
        review_record_for(invalid_candidate, category_match: true, tag_match: true)
      ])

      assert_raises(Taxonomy::PublishReclassification::QualityGateFailed) do
        Taxonomy::PublishReclassification.call(reviewer:, confirmation: "publish-taxonomy-v2", review_path: path, scope: Resource.where(id: [ valid_resource.id, invalid_resource.id ]), target_per_kind: 1)
      end

      assert_predicate valid_candidate.reload, :review_pending?
      assert_predicate invalid_candidate.reload, :review_pending?
      assert_equal original_current_ids.fetch(valid_resource), valid_resource.reload.current_revision_id
      assert_equal original_current_ids.fetch(invalid_resource), invalid_resource.reload.current_revision_id
      assert_equal 0, AdminAuditLog.where(auditable: [ valid_candidate, invalid_candidate ]).count
    end
  end

  private

  def create_published_resource(kind:, slug:, categories: [ "coding-development" ], tags: [ "ruby", "testing" ])
    provider = %i[mcp skill].include?(kind) ? :github : kind.to_s.delete_suffix("_article").to_sym
    resource = Resource.create!(
      kind:,
      slug:,
      canonical_url: "https://example.com/#{slug}",
      normalized_canonical_url: "https://example.com/#{slug}",
      source_provider: provider,
      external_uid: slug
    )
    revision = resource.revisions.create!(
      origin: :imported,
      title: slug.titleize,
      source_excerpt: "RailsでAI開発を支援する公開リソースです。",
      source_fingerprint: "#{slug}-v1",
      author_name: "Author",
      ai_summary: "AI開発に役立つ日本語の要約です。",
      ai_provider: "nvidia",
      ai_model: "summary-model",
      prompt_version: "summary-v1",
      summary_basis: "source",
      summary_input_sha256: Digest::SHA256.hexdigest("#{slug}:summary"),
      summary_generated_at: Time.current,
      capabilities: [ "分類候補を検証する" ],
      key_points: [ "承認済み改訂は不変" ],
      suggested_category_slugs: categories,
      suggested_tag_slugs: tags,
      taxonomy_origin: :admin,
      taxonomy_status: :succeeded,
      taxonomy_confidence: 0.95,
      summary_status: :succeeded,
      review_status: :review_pending
    )
    Editorial::ApproveAndPublish.call(revision:, reviewer: users(:admin))
    resource.reload
  end

  def create_candidate_for(
    resource,
    categories: [ "automation-integration" ],
    tags: [ "ruby", "api-integration" ],
    confidence: 0.95,
    taxonomy_status: :succeeded,
    review_status: :draft
  )
    candidate = Taxonomy::BuildReclassificationCandidate.call(resource:)
    candidate.update!(
      suggested_category_slugs: categories,
      suggested_tag_slugs: tags,
      search_keywords: [ "taxonomy v2" ],
      taxonomy_confidence: confidence,
      taxonomy_provider: "test",
      taxonomy_model: "test-taxonomizer",
      taxonomy_prompt_version: "catalog-taxonomy-v2",
      taxonomy_generated_at: Time.current,
      taxonomy_status:,
      review_status:
    )
    candidate
  end

  def review_record_for(candidate, category_match:, tag_match:, required_review: false)
    {
      "resource_id" => candidate.resource_id,
      "kind" => candidate.resource.kind,
      "title" => candidate.title,
      "category_slugs" => candidate.suggested_category_slugs,
      "tag_slugs" => candidate.suggested_tag_slugs,
      "confidence" => candidate.taxonomy_confidence.to_f,
      "required_review" => required_review,
      "category_match" => category_match,
      "tag_match" => tag_match,
      "review_note" => nil
    }
  end

  def write_review(path, records)
    File.write(path, JSON.pretty_generate({
      "format" => "ai-dev-zukan.taxonomy-review",
      "version" => 1,
      "taxonomy_version" => "taxonomy-v2",
      "generated_at" => Time.current.iso8601,
      "records_sha256" => Digest::SHA256.hexdigest(JSON.generate(records)),
      "records" => records
    }))
  end

  def with_review_decisions(records)
    records.map do |record|
      record.merge("category_match" => true, "tag_match" => true)
    end
  end
end
