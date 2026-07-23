class SkuSyncJob < ApplicationJob
  queue_as :default

  def perform(sku_sync_id)
    sku_sync = SkuSync.find(sku_sync_id)
    Skus::SyncService.call(sku_sync)
  end
end
