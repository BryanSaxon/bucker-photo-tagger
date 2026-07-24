class SkusController < ApplicationController
  # The SKU library: browse/search the synced catalog and see sync status.
  def index
    @query = params[:q].to_s.strip
    @category = params[:category].to_s.strip
    @skus = Sku.search(@query).in_category(@category).ordered.limit(200)
    @total = Sku.count
    @category_codes = Sku.category_codes
    @latest_sync = SkuSync.latest
  end

  # Detail page for a single SKU: catalog fields, variants, image metadata,
  # and the photos it has been tagged in.
  def show
    @sku = Sku.find(params[:id])
    @tagged_photos = @sku.photos.complete.recent.with_attached_image
  end

  # Enqueue a pull of this SKU's image bytes from NewStart. Runs in the
  # background so the request returns immediately.
  def fetch_image
    @sku = Sku.find(params[:id])
    SkuImageFetchJob.perform_later(@sku.id)
    redirect_to sku_path(@sku), notice: "Fetching image from NewStart…"
  end
end
