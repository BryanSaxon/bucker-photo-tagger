class SkuSyncJob < ApplicationJob
  queue_as :default

  def perform(sku_sync_id)
    sku_sync = SkuSync.find(sku_sync_id)
    Catalog::SyncService.call(sku_sync)
  end
end
