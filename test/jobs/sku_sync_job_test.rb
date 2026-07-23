require "test_helper"

class SkuSyncJobTest < ActiveJob::TestCase
  test "runs the sync service for the given record" do
    sync = SkuSync.create!(status: :running)

    # No API configured in test → the service should record a failure, not raise.
    assert_nothing_raised do
      SkuSyncJob.perform_now(sync.id)
    end
    assert sync.reload.failed?
  end
end
