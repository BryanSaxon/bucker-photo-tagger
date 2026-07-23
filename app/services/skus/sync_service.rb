module Skus
  # Syncs the local Sku catalog from the NewStart /product_library endpoint.
  #
  # The remote catalog is the source of truth and has no incremental "changed
  # since" parameter, so every run is a full re-fetch + upsert keyed on
  # product_code. Progress/outcome is recorded on the passed-in SkuSync record
  # so the UI can show sync status.
  class SyncService
    BATCH_SIZE = 500

    def self.call(sku_sync, client: Newstart::Client.new)
      new(sku_sync, client).call
    end

    def initialize(sku_sync, client)
      @sku_sync = sku_sync
      @client = client
    end

    def call
      @sku_sync.update!(status: :running, started_at: Time.current)

      products = @client.product_library
      count = upsert(products)

      @sku_sync.mark_completed!(count)
      @sku_sync
    rescue => e
      Rails.logger.error("[Skus::SyncService] #{e.class}: #{e.message}")
      @sku_sync.mark_failed!("#{e.class}: #{e.message}")
      @sku_sync
    end

    private

    # Map raw API product hashes onto Sku columns and upsert in batches.
    def upsert(products)
      now = Time.current
      rows = products.filter_map do |product|
        code = product["product_code"].presence
        next unless code

        {
          product_code: code,
          short_description: product["short_description"],
          category_code: product["category_code"],
          subcategory_code: product["subcategory_code"],
          attribute1_desc: product["attribute1_desc"],
          attribute1: product["attribute1"],
          image_flag: product["image"],
          source_modified_at: product["lastmoddatetime"],
          created_at: now,
          updated_at: now
        }
      end

      # De-dupe on product_code in case the catalog repeats a code (upsert_all
      # rejects a batch containing duplicate conflict keys).
      rows.uniq! { |r| r[:product_code] }

      rows.each_slice(BATCH_SIZE) do |batch|
        # updated_at is managed automatically by upsert_all; listing it in
        # update_only would produce a duplicate SET clause.
        Sku.upsert_all(batch, unique_by: :product_code, update_only:
          %i[short_description category_code subcategory_code attribute1_desc
             attribute1 image_flag source_modified_at])
      end

      rows.size
    end
  end
end
