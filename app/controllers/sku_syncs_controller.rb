class SkuSyncsController < ApplicationController
  # Manually trigger a background SKU catalog sync. Guards against overlapping
  # runs so a processor can't queue several syncs at once.
  def create
    if SkuSync.in_progress?
      redirect_to skus_path, alert: "A SKU sync is already running."
      return
    end

    sku_sync = SkuSync.create!(status: :running, started_at: Time.current)
    SkuSyncJob.perform_later(sku_sync.id)

    redirect_to skus_path, notice: "SKU sync started. This runs in the background."
  end
end
