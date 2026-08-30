require "test_helper"
require "rake"

class CatalogSnapshotTasksTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "catalog:snapshot:release_existing" }
  end

  test "exposes existing catalog snapshot release as a guarded snapshot task" do
    task = Rake::Task["catalog:snapshot:release_existing"]

    assert_equal "catalog:snapshot:release_existing", task.name
    refute_equal InitialCatalog::ReleaseSnapshot::CONFIRMATION, "publish"
  end
end
