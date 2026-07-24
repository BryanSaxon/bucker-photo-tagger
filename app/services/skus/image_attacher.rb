module Skus
  # Pulls the actual image bytes for a SKU from the NewStart
  # /product_images/{image_name}/file_contents endpoint and saves them as
  # ActiveStorage attachments on the SKU (Sku#images).
  #
  # Which images to fetch is driven by metadata, not guesswork:
  #   * Pass `images:` (the full /product_images index) to attach *every* live
  #     image the catalog lists for the SKU's product_code — this is what the
  #     batch/backfill path does so it fetches the index only once.
  #   * Omit it and the service falls back to the single primary image whose
  #     filename the sync already stored on the SKU (Sku#image_filename) — handy
  #     for an on-demand "fetch this one SKU's image" action.
  #
  # The operation is idempotent: an image whose filename is already attached is
  # skipped, so re-running only fills in what's missing. A download failure for
  # one image is logged and skipped rather than aborting the rest.
  class ImageAttacher
    def self.call(sku, client: Newstart::Client.new, images: nil)
      new(sku, client, images).call
    end

    def initialize(sku, client, images)
      @sku = sku
      @client = client
      @images = images
    end

    # Returns the number of images newly attached this run.
    def call
      targets = image_targets
      return 0 if targets.empty?

      attached = 0
      targets.each do |meta|
        filename = meta[:filename].presence
        next if filename.nil?
        next if already_attached?(filename)

        attached += 1 if download_and_attach(filename)
      end
      attached
    end

    private

    # The list of { filename:, content_type: } to fetch for this SKU.
    def image_targets
      if @images
        catalog_targets(@images)
      elsif @sku.image_filename.present?
        [ { filename: @sku.image_filename, content_type: @sku.image_mimetype } ]
      else
        []
      end
    end

    # Filter the full product_images index down to this SKU's live images.
    def catalog_targets(images)
      images.filter_map do |img|
        next unless img["product_code"] == @sku.product_code
        next if img["isarchived"] || img["isdeleted"]

        filename = img["filename"].presence
        next unless filename

        { filename: filename, content_type: img["filemimetype"] }
      end.uniq { |m| m[:filename] }
    end

    def already_attached?(filename)
      @sku.images.any? { |att| att.filename.to_s == filename }
    end

    def download_and_attach(filename)
      file = @client.product_image_file_contents(filename)
      return false if file.body.to_s.empty?

      @sku.images.attach(
        io: StringIO.new(file.body),
        filename: file.filename.presence || filename,
        content_type: file.content_type
      )
      true
    rescue Newstart::Client::RequestError => e
      Rails.logger.warn(
        "[Skus::ImageAttacher] #{@sku.product_code} image #{filename.inspect} failed: #{e.message}"
      )
      false
    end
  end
end
