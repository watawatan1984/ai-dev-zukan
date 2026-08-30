require "test_helper"

class InitialCatalog::BootstrapTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues source imports and leaves collection and summaries to Solid Queue" do
    result = nil
    assert_enqueued_jobs 4, only: SourceImportJob do
      result = InitialCatalog::Bootstrap.call(limit: 100)
    end

    assert result.complete?
    assert_equal 100, result.target
    assert_equal InitialCatalog::Bootstrap::SOURCE_KINDS.keys, result.enqueued_sources
    InitialCatalog::Bootstrap::SOURCE_KINDS.each_key do |source_name|
      assert_enqueued_with(job: SourceImportJob, args: [ source_name, { limit: 100 } ])
    end
  end
end
