class SkuImageFetchJob < ApplicationJob
  queue_as :default

  # Pulls and attaches the image(s) for one SKU on demand. Uses the metadata the
  # sync already stored on the SKU, so it does not need to re-fetch the full
  # product-image index.
  def perform(sku_id)
    sku = Sku.find_by(id: sku_id)
    return unless sku

    Skus::ImageAttacher.call(sku)
  end
end
