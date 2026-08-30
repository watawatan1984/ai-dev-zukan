namespace :catalog do
  desc "Collect and summarize the initial 100 resources for every catalog kind"
  task bootstrap: :environment do
    target = ENV.fetch("BOOTSTRAP_PER_KIND", 100).to_i.clamp(1, 100)
    selected_model = ENV["BOOTSTRAP_NVIDIA_MODEL"].presence ||
      ENV["NVIDIA_NIM_MODEL"].presence ||
      ENV["NVIDIA_AI_MODEL1"].presence
    progress = lambda do |payload|
      puts(payload.merge(at: Time.current.iso8601).to_json)
      $stdout.flush
    end
    result = InitialCatalog::Bootstrap.call(
      limit: target,
      summarizer_factory: -> { Ai::NvidiaSummarizer.new(model: selected_model) },
      import_sources: ENV["BOOTSTRAP_SKIP_IMPORT"] != "1",
      progress:
    )

    puts JSON.pretty_generate(
      target: result.target,
      counts: result.counts,
      failures: result.failures
    )
    abort "Initial catalog is incomplete" unless result.complete?
  end

  namespace :bootstrap do
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
  end
end
