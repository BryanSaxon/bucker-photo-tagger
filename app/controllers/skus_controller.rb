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
end
