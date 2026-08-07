class SkusController < ApplicationController
  # The SKU library: browse/search the synced catalog and see sync status.
  def index
    @query = params[:q].to_s.strip
    # The catalog is an ERP price list; by default show only what a designer
    # could actually tag. "Show everything" is there for reference.
    @show_all = params[:all] == "1"

    scope = (@show_all ? Sku.all : Sku.taggable).search(@query)
    # One row per visual thing, with how many line items it stands for.
    @group_sizes = Sku.group_sizes(scope)
    @pagy, @skus = pagy(scope.representatives.ordered)

    @total = Sku.count
    @taggable_total = Sku.taggable.count
    @latest_sync = SkuSync.latest
  end

  # Detail page for a single SKU: catalog fields, variants, image metadata,
  # and the photos it has been tagged in.
  def show
    @sku = Sku.find(params[:id])
    # distinct: a photo tagging this product in two finishes joins twice and
    # would otherwise show up as duplicate thumbnails.
    @tagged_photos = @sku.photos.complete.distinct.recent.with_attached_image
    # "Where is the matte black one installed?" — counts per recorded finish.
    @tagged_variants = @sku.tagged_variants
  end
end
