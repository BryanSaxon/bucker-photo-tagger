require "test_helper"

# Thumbnails outlive the images behind them: a HEIC source is replaced by its
# JPEG conversion, photos get deleted, and old uploads can point at objects a
# previous storage configuration no longer holds. None of that should be a 500.
class PhotoThumbnailsTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  def create_photo(name: "Kitchen", fixture: "sample.png", filename: "sample.png", content_type: "image/png")
    photo = Photo.new(name: name)
    photo.image.attach(io: file_fixture(fixture).open, filename: filename, content_type: content_type)
    photo.save!
    photo
  end

  def thumbnail_path(photo)
    variant = photo.image.variant(:thumb)
    rails_blob_representation_path(variant.blob.signed_id, variant.variation.key, variant.blob.filename)
  end

  test "a thumbnail whose blob is purged mid-transform 404s instead of erroring" do
    photo = create_photo
    blob = photo.image.blob
    path = thumbnail_path(photo)

    # The production race, reproduced: the request finds the blob and starts the
    # multi-second transform, and the purge (a HEIC conversion replacing its
    # source, or a deleted photo) lands before the variant record is inserted.
    # That insert used to raise ActiveRecord::InvalidForeignKey and return a 500.
    subscription = ActiveSupport::Notifications.subscribe(/download\.active_storage/) do
      ActiveStorage::Attachment.where(blob_id: blob.id).delete_all
      ActiveStorage::Blob.where(id: blob.id).delete_all
    end

    begin
      get path
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end

    assert_response :not_found
    assert_not ActiveStorage::VariantRecord.exists?(blob_id: blob.id)
  end

  test "a thumbnail whose file is missing from storage 404s instead of erroring" do
    photo = create_photo
    blob = photo.image.blob
    path = thumbnail_path(photo)

    # A blob row with no object behind it — what uploads made under an older
    # storage configuration look like now (ActiveStorage::FileNotFoundError,
    # or a bare Aws::S3::Errors::NotFound on R2).
    blob.service.delete(blob.key)

    get path

    assert_response :not_found
  end

  test "a thumbnail whose blob row is already gone 404s" do
    photo = create_photo
    blob = photo.image.blob
    path = thumbnail_path(photo)
    ActiveStorage::Attachment.where(blob_id: blob.id).delete_all
    ActiveStorage::Blob.where(id: blob.id).delete_all

    get path

    assert_response :not_found
  end

  test "an unrelated failure still surfaces rather than being swallowed as a 404" do
    photo = create_photo
    blob = photo.image.blob
    # A transformation the processor refuses. Nothing is missing here, so the
    # rescue must let it through instead of reporting a tidy 404.
    variation_key = ActiveStorage::Variation.encode(combine_options: { resize: "10x10" })

    assert_raises(StandardError) do
      get rails_blob_representation_path(blob.signed_id, variation_key, blob.filename)
    end
  end

  test "the grid holds off on the thumbnail until a HEIC upload has been converted" do
    photo = create_photo(name: "Sunroom", fixture: "sample.heic",
      filename: "IMG_2168.HEIC", content_type: "image/heic")
    sign_in_as(@user)

    get photos_path

    assert_response :success
    assert_select ".photo-card__pending", text: "Preparing…"
    assert_select ".photo-card__thumb img", count: 0
    assert_not photo.thumbnail_ready?
  end

  test "the grid shows the thumbnail once the image is displayable" do
    create_photo(name: "Kitchen")
    sign_in_as(@user)

    get photos_path

    assert_response :success
    assert_select ".photo-card__thumb img"
    assert_select ".photo-card__pending", count: 0
  end
end
