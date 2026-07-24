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
    @sku_images = @sku.sku_images.primary_first
    @tagged_photos = @sku.photos.complete.recent.with_attached_image
  end
end
