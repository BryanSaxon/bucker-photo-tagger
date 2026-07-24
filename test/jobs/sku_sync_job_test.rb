require "test_helper"

class SkuSyncJobTest < ActiveJob::TestCase
  test "looks up the record and runs the sync service (no real network call)" do
    sync = SkuSync.create!(status: :running)
    received = nil

    # Swap the service for a stub so the job test never touches the real API.
    original = Catalog::SyncService.method(:call)
    Catalog::SyncService.define_singleton_method(:call) do |record, **|
      received = record
      record.mark_completed!(0)
    end

    begin
      SkuSyncJob.perform_now(sync.id)
    ensure
      Catalog::SyncService.define_singleton_method(:call, original)
    end

    assert_equal sync.id, received.id
    assert sync.reload.completed?
  end
end
