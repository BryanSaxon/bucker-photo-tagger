module Skus
  # Syncs the local Sku catalog from the NewStart /product_library endpoint,
  # enriched with image metadata from /product_images.
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
      images = fetch_images
      count = upsert(products, images)

      @sku_sync.mark_completed!(count)
      @sku_sync
    rescue => e
      Rails.logger.error("[Skus::SyncService] #{e.class}: #{e.message}")
      @sku_sync.mark_failed!("#{e.class}: #{e.message}")
      @sku_sync
    end

    private

    # Image metadata is best-effort: a failure fetching images must never fail
    # the whole catalog sync.
    def fetch_images
      @client.product_images
    rescue => e
      Rails.logger.warn("[Skus::SyncService] image fetch failed: #{e.class}: #{e.message}")
      []
    end

    # Build product_code => image metadata, choosing a representative (primary)
    # image per product and counting how many live images it has.
    def image_index(images)
      by_code = Hash.new { |h, k| h[k] = [] }
      images.each do |img|
        code = img["product_code"].presence
        next if code.nil? || img["isarchived"] || img["isdeleted"]
        by_code[code] << img
      end

      by_code.transform_values do |imgs|
        primary = imgs.find { |i| i["source_type"] == "Product" } || imgs.first
        {
          image_filename: primary["filename"],
          image_mimetype: primary["filemimetype"],
          image_file_id: primary["file_id"],
          images_count: imgs.size
        }
      end
    end

    # Map raw API product hashes (plus image metadata) onto Sku columns and
    # upsert in batches.
    def upsert(products, images)
      now = Time.current
      index = image_index(images)

      rows = products.filter_map do |product|
        code = product["product_code"].presence
        next unless code

        meta = index[code] || {}
        {
          product_code: code,
          short_description: product["short_description"],
          category_code: product["category_code"],
          subcategory_code: product["subcategory_code"],
          attribute1_desc: product["attribute1_desc"],
          attribute1: product["attribute1"],
          image_flag: product["image"],
          source_modified_at: product["lastmoddatetime"],
          image_filename: meta[:image_filename],
          image_mimetype: meta[:image_mimetype],
          image_file_id: meta[:image_file_id],
          images_count: meta[:images_count] || 0,
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
             attribute1 image_flag source_modified_at
             image_filename image_mimetype image_file_id images_count])
      end

      rows.size
    end
  end
end
