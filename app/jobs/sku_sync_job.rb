class SkuSyncJob < ApplicationJob
  queue_as :default

  # The interactive "Refresh" sync populates the full catalog EXCEPT per-lot
  # configured selections, which would add ~one API call per lot (thousands) and
  # make the run impractically long. Lot selections are synced separately (pass
  # fetch_selections: true, optionally lot_limit:) when that detail is needed.
  def perform(sku_sync_id, fetch_selections: false, lot_limit: nil)
    sku_sync = SkuSync.find(sku_sync_id)
    Catalog::SyncService.call(sku_sync, fetch_selections: fetch_selections, lot_limit: lot_limit)
  end
end
