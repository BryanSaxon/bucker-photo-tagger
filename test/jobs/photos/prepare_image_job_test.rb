require "test_helper"

module Photos
  class PrepareImageJobTest < ActiveJob::TestCase
    def photo_with(fixture, filename, content_type)
      photo = Photo.new(name: File.basename(filename, ".*"))
      photo.image.attach(io: file_fixture(fixture).open, filename: filename,
        content_type: content_type)
      photo.save!
      photo
    end

    test "converts a HEIC upload to JPEG and drops the original blob" do
      skip "libvips has no HEIF decoder here" unless ImageSupport.heic_available?

      photo = photo_with("sample.heic", "IMG_0042.HEIC", "image/heic")
      original = photo.image.blob

      perform_enqueued_jobs { PrepareImageJob.perform_now(photo.id) }

      photo.reload
      assert_equal "image/jpeg", photo.image.blob.content_type
      assert_equal "IMG_0042.jpg", photo.image.blob.filename.to_s
      assert_not ActiveStorage::Blob.exists?(original.id), "the HEIC blob was left behind"
    end

    test "the replaced blob is purged after a grace period, not immediately" do
      skip "libvips has no HEIF decoder here" unless ImageSupport.heic_available?

      photo = photo_with("sample.heic", "IMG_0044.HEIC", "image/heic")
      original = photo.image.blob

      # Thumbnail requests for the original can still be in flight — a grid page
      # rendered before the conversion loads them lazily — and purging out from
      # under them is what turned into 500s in production.
      assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ original ],
        at: PrepareImageJob::PURGE_GRACE.from_now) do
        PrepareImageJob.perform_now(photo.id)
      end

      assert ActiveStorage::Blob.exists?(original.id), "the original was purged straight away"
    end

    test "leaves a JPEG alone and simply warms its thumbnail" do
      photo = photo_with("sample.png", "kitchen.png", "image/png")
      blob = photo.image.blob

      PrepareImageJob.perform_now(photo.id)

      assert_equal blob, photo.reload.image.blob
      assert photo.image.variant(:thumb).processed.present?
    end

    test "is idempotent — a second run leaves an already-converted photo alone" do
      skip "libvips has no HEIF decoder here" unless ImageSupport.heic_available?

      photo = photo_with("sample.heic", "IMG_0043.heic", "image/heic")
      perform_enqueued_jobs { PrepareImageJob.perform_now(photo.id) }
      converted = photo.reload.image.blob

      perform_enqueued_jobs { PrepareImageJob.perform_now(photo.id) }

      assert_equal converted, photo.reload.image.blob
    end

    test "a deleted photo is discarded rather than retried forever" do
      photo = photo_with("sample.png", "gone.png", "image/png")
      id = photo.id
      photo.destroy

      assert_nothing_raised { PrepareImageJob.perform_now(id) }
    end

    test "creating a photo enqueues preparation" do
      assert_enqueued_with(job: PrepareImageJob) do
        photo_with("sample.png", "queued.png", "image/png")
      end
    end
  end
end
