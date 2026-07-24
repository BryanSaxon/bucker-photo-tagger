module Skus
  # Backwards-compatible entry point that syncs ONLY the product catalog and
  # records progress/outcome on a SkuSync. The heavy lifting lives in
  # Catalog::ProductsSyncer; the full catalog graph is synced by
  # Catalog::SyncService (which this no longer drives).
  class SyncService
    def self.call(sku_sync, client: Newstart::Client.new)
      new(sku_sync, client).call
    end

    def initialize(sku_sync, client)
      @sku_sync = sku_sync
      @client = client
    end

    def call
      @sku_sync.update!(status: :running, started_at: Time.current)
      count = Catalog::ProductsSyncer.call(client: @client)
      @sku_sync.mark_completed!(count)
      @sku_sync
    rescue => e
      Rails.logger.error("[Skus::SyncService] #{e.class}: #{e.message}")
      @sku_sync.mark_failed!("#{e.class}: #{e.message}")
      @sku_sync
    end
  end
end
