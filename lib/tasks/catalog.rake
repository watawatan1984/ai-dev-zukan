namespace :catalog do
  desc "Collect and summarize the initial 100 resources for every catalog kind"
  task bootstrap: :environment do
    target = ENV.fetch("BOOTSTRAP_PER_KIND", 100).to_i.clamp(1, 100)
    result = InitialCatalog::Bootstrap.call(limit: target)

    puts JSON.pretty_generate(
      target: result.target,
      enqueued_sources: result.enqueued_sources,
      next_step: "Solid Queue processes source imports and NVIDIA summaries; run catalog:bootstrap:report afterwards"
    )
    abort "Initial catalog jobs were not fully enqueued" unless result.complete?
  end

  namespace :bootstrap do
    desc "Requeue failed or pending initial summaries through Solid Queue"
    task retry_summaries: :environment do
      result = InitialCatalog::EnqueuePendingSummaries.call(
        target: ENV.fetch("BOOTSTRAP_PER_KIND", 100)
      )
      puts JSON.pretty_generate(enqueued_revision_ids: result.enqueued_revision_ids)
    end

    desc "Archive imported MCP-adjacent repositories that are not explicit MCP servers"
    task curate_mcp: :environment do
      result = InitialCatalog::ArchiveIrrelevantMcp.call
      puts JSON.pretty_generate(
        selected_count: result.selected_count,
        archived_ids: result.archived_ids,
        reactivated_ids: result.reactivated_ids
      )
    end

    desc "Archive imported repositories that are not explicit agent Skills"
    task curate_skill: :environment do
      result = InitialCatalog::ArchiveIrrelevantSkill.call
      puts JSON.pretty_generate(
        selected_count: result.selected_count,
        archived_ids: result.archived_ids,
        reactivated_ids: result.reactivated_ids
      )
    end

    desc "Normalize long summaries and requeue non Japanese summaries"
    task repair: :environment do
      result = InitialCatalog::RepairQuality.call
      puts JSON.pretty_generate(trimmed_ids: result.trimmed_ids, requeued_ids: result.requeued_ids)
    end

    desc "Report initial catalog counts and summary quality"
    task report: :environment do
      report = InitialCatalog::QualityReport.call(
        target: ENV.fetch("BOOTSTRAP_PER_KIND", 100)
      )
      puts JSON.pretty_generate(target: report.target, acceptable: report.acceptable?, counts: report.counts)
      abort "Initial catalog quality gate failed" unless report.acceptable?
    end

    desc "Publish the reviewed initial catalog with an explicit admin confirmation"
    task publish: :environment do
      admin = User.find_by!(email: ENV.fetch("ADMIN_EMAIL"))
      result = InitialCatalog::Publish.call(
        reviewer: admin,
        confirmation: ENV["CONFIRM"],
        limit: ENV.fetch("BOOTSTRAP_PER_KIND", 100)
      )
      puts JSON.pretty_generate(target: result.target, published_counts: result.published_counts)
    end

    desc "Publish the approved launch catalog with a locked system reviewer"
    task release: :environment do
      confirmation = ENV["INITIAL_CATALOG_RELEASE"]
      abort "Set INITIAL_CATALOG_RELEASE=publish to run the initial release" unless confirmation == "publish"

      reviewer = InitialCatalog::ReleaseReviewer.call
      result = InitialCatalog::Publish.call(
        reviewer:,
        confirmation:,
        limit: ENV.fetch("BOOTSTRAP_PER_KIND", 100)
      )
      puts JSON.pretty_generate(
        target: result.target,
        reviewer: reviewer.email,
        published_counts: result.published_counts
      )
    end
  end

  namespace :snapshot do
    desc "Export the reviewed initial catalog to a portable, checksummed artifact"
    task export: :environment do
      result = InitialCatalog::ExportSnapshot.call(
        path: ENV.fetch("INITIAL_CATALOG_SNAPSHOT", Rails.root.join("db/seed_data/initial_catalog.json")),
        target: ENV.fetch("BOOTSTRAP_PER_KIND", 100)
      )
      puts JSON.pretty_generate(path: result.path, counts: result.counts, checksum: result.checksum)
    end

    desc "Import the portable initial catalog without publishing it"
    task import: :environment do
      result = InitialCatalog::ImportSnapshot.call(
        path: ENV.fetch("INITIAL_CATALOG_SNAPSHOT", Rails.root.join("db/seed_data/initial_catalog.json")),
        target: ENV.fetch("BOOTSTRAP_PER_KIND", 100)
      )
      puts JSON.pretty_generate(
        target: result.target,
        created_revisions: result.created_revisions,
        unchanged_revisions: result.unchanged_revisions,
        counts: result.counts
      )
    end
  end
end
