class SkusController < ApplicationController
  # The SKU library: browse/search the synced catalog and see sync status.
  def index
    @query = params[:q].to_s.strip
    @pagy, @skus = pagy(Sku.search(@query).ordered)
    @total = Sku.count
    @latest_sync = SkuSync.latest
  end

  # Detail page for a single SKU: catalog fields, variants, image metadata,
  # and the photos it has been tagged in.
  def show
    @sku = Sku.find(params[:id])
    @tagged_photos = @sku.photos.complete.recent.with_attached_image
  end
end
