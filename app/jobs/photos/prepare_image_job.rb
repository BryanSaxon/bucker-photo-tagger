module Photos
  # Runs once per new Photo: converts a HEIC/HEIF source to JPEG, then warms the
  # :thumb variant.
  #
  # The ordering is why this job exists at all. The :thumb variant used to be
  # declared `preprocessed: true`, which enqueues the transform on attach — so a
  # HEIC upload raced a conversion job and usually lost, failing the transform
  # and leaving a blank thumbnail with no user-facing error. Normalising first
  # and warming second makes the sequence explicit.
  class PrepareImageJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound
    retry_on Vips::Error, wait: :polynomially_longer, attempts: 3

    CONVERTIBLE_TYPES = ImageSupport::CONVERTIBLE_TYPES

    # How long the replaced HEIC blob sticks around. A grid page rendered just
    # before the conversion still holds thumbnail URLs for the original, and the
    # browser loads them lazily as the processor scrolls. Purging immediately
    # meant those requests downloaded the blob, spent seconds transforming it,
    # and then blew up inserting the variant record for a row that no longer
    # existed (PG::ForeignKeyViolation on active_storage_variant_records, a 500
    # per thumbnail). The grace period lets those stragglers finish.
    PURGE_GRACE = 30.minutes

    def perform(photo_id)
      photo = Photo.find(photo_id)
      return unless photo.image.attached?

      normalize!(photo) if CONVERTIBLE_TYPES.include?(photo.image.blob.content_type)
      photo.image.variant(:thumb).processed
    end

    private

    # Replace the HEIC blob with a JPEG rendition and drop the original. A
    # 12 MP HEIC decodes to ~48 MB, but libvips streams, so peak memory stays
    # bounded as long as this queue isn't run wide.
    def normalize!(photo)
      original = photo.image.blob

      photo.image.blob.open do |source|
        jpeg = ImageProcessing::Vips
          .source(source)
          .convert("jpg")
          # strip: false keeps EXIF orientation — iPhone HEICs are almost always
          # rotation-tagged, and dropping it turns portraits sideways.
          .saver(quality: 90, strip: false)
          .call

        photo.image.attach(
          io: jpeg,
          filename: "#{File.basename(original.filename.to_s, '.*')}.jpg",
          content_type: "image/jpeg"
        )
      end

      ActiveStorage::PurgeJob.set(wait: PURGE_GRACE).perform_later(original)
      Rails.logger.info({ event: "photos.heic_converted", photo_id: photo.id }.to_json)
    end
  end
end
