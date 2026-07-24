module Skus
  # Backfills image bytes for many SKUs at once. Fetches the full
  # /product_images index a single time, then attaches every live image to its
  # matching SKU via Skus::ImageAttacher. Idempotent, so it can be re-run to pick
  # up SKUs whose downloads previously failed.
  #
  # Returns the number of images newly attached across all SKUs.
  class ImageBackfillService
    def self.call(scope: Sku.where(image_flag: "BookYesImage"), client: Newstart::Client.new)
      new(scope, client).call
    end

    def initialize(scope, client)
      @scope = scope
      @client = client
    end

    def call
      images = @client.product_images
      by_code = images.group_by { |img| img["product_code"] }

      attached = 0
      @scope.find_each do |sku|
        sku_images = by_code[sku.product_code]
        next if sku_images.blank?

        attached += Skus::ImageAttacher.call(sku, client: @client, images: sku_images)
      end
      attached
    end
  end
end
