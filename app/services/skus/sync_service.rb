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
      sync_image_records(images)
      prune_absent(products)

      @sku_sync.mark_completed!(count)
      @sku_sync
    rescue => e
      Rails.logger.error("[Skus::SyncService] #{e.class}: #{e.message}")
      @sku_sync.mark_failed!("#{e.class}: #{e.message}")
      @sku_sync
    end

    private

    # Full-replace semantics: remove SKUs that are no longer in the catalog so a
    # resync reconciles rather than only accumulating. SKUs still tagged in a
    # photo are kept, so a processor's saved selections are never silently lost.
    #
    # Guarded against an empty/failed catalog response so a transient blank
    # payload can't wipe the whole table.
    def prune_absent(products)
      api_codes = products.filter_map { |p| p["product_code"].presence }.uniq
      return 0 if api_codes.empty?

      removed = Sku.where.not(product_code: api_codes).where.missing(:photo_skus).delete_all
      Rails.logger.info("[Skus::SyncService] pruned #{removed} stale SKUs") if removed.positive?
      removed
    end

    # Image metadata is best-effort: a failure fetching images must never fail
    # the whole catalog sync.
    def fetch_images
      @client.product_images
    rescue => e
      Rails.logger.warn("[Skus::SyncService] image fetch failed: #{e.class}: #{e.message}")
      []
    end

    # Persist the full per-image metadata as SkuImage rows so the app keeps its
    # own copy of the catalog's image list, keyed by product_code. This is what
    # lets a SKU surface every variant image rather than the single condensed
    # primary stored on the skus row.
    #
    # Best-effort like the rest of the image handling: a problem here logs and
    # returns without failing the catalog sync.
    def sync_image_records(images)
      return if images.blank?

      sku_ids = Sku.pluck(:product_code, :id).to_h
      now = Time.current

      rows = images.filter_map do |img|
        file_id = img["file_id"].presence
        code = img["product_code"].presence
        next unless file_id && code

        sku_id = sku_ids[code]
        next unless sku_id # an image for a product not in the catalog

        {
          sku_id: sku_id,
          product_code: code,
          file_id: file_id,
          filename: img["filename"],
          filemimetype: img["filemimetype"],
          title: img["title"],
          description: img["description"],
          source_type: img["source_type"],
          attribute1: img["attribute1"],
          attribute2: img["attribute2"],
          archived: ActiveModel::Type::Boolean.new.cast(img["isarchived"]) || false,
          source_modified_at: img["modifieddate"],
          created_at: now,
          updated_at: now
        }
      end

      # file_id is globally unique in the catalog and is our conflict key, so a
      # repeated file_id in the payload would break the batch — de-dupe first.
      rows.uniq! { |r| r[:file_id] }

      rows.each_slice(BATCH_SIZE) do |batch|
        SkuImage.upsert_all(batch, unique_by: :file_id, update_only:
          %i[sku_id product_code filename filemimetype title description
             source_type attribute1 attribute2 archived source_modified_at])
      end

      prune_image_records(rows)
    rescue => e
      Rails.logger.warn("[Skus::SyncService] image record sync failed: #{e.class}: #{e.message}")
    end

    # Full-replace semantics for image records: drop rows whose file_id is no
    # longer in the catalog. Guarded so an empty image payload can't wipe them.
    def prune_image_records(rows)
      file_ids = rows.map { |r| r[:file_id] }
      return if file_ids.empty?

      removed = SkuImage.where.not(file_id: file_ids).delete_all
      Rails.logger.info("[Skus::SyncService] pruned #{removed} stale image records") if removed.positive?
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
