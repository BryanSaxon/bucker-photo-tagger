require "test_helper"

class PhotoSkuTest < ActiveSupport::TestCase
  setup do
    @photo = Photo.new(name: "Kitchen")
    @photo.image.attach(io: file_fixture("sample.png").open, filename: "sample.png", content_type: "image/png")
    @photo.save!
    @sku = Sku.create!(product_code: "ABC")
  end

  test "coordinates may be nil (unpinned)" do
    ps = PhotoSku.new(photo: @photo, sku: @sku)
    assert ps.valid?
    assert_not ps.pinned?
  end

  test "normalized coordinates within 0..1 are valid" do
    ps = PhotoSku.new(photo: @photo, sku: @sku, pos_x: 0.5, pos_y: 0.25)
    assert ps.valid?
    assert ps.pinned?
  end

  test "coordinates outside 0..1 are invalid" do
    assert_not PhotoSku.new(photo: @photo, sku: @sku, pos_x: 1.5, pos_y: 0.5).valid?
  end

  test "a sku can only be attached to a photo once under the same variant" do
    PhotoSku.create!(photo: @photo, sku: @sku)
    assert_not PhotoSku.new(photo: @photo, sku: @sku).valid?
  end

  test "the same sku may be attached twice under different variants" do
    PhotoSku.create!(photo: @photo, sku: @sku, variant_value: "Matte Black")
    assert PhotoSku.new(photo: @photo, sku: @sku, variant_value: "Chrome").valid?
  end

  test "the same sku and variant cannot be attached twice" do
    PhotoSku.create!(photo: @photo, sku: @sku, variant_value: "Chrome")
    assert_not PhotoSku.new(photo: @photo, sku: @sku, variant_value: "Chrome").valid?
  end

  test "variant_value defaults to an empty string rather than nil" do
    ps = PhotoSku.create!(photo: @photo, sku: @sku)
    assert_equal "", ps.reload.variant_value
    assert_not ps.variant?
  end

  test "variant_value is stripped" do
    ps = PhotoSku.create!(photo: @photo, sku: @sku, variant_value: "  Chrome  ")
    assert_equal "Chrome", ps.variant_value
  end

  test "variant_in_catalog? distinguishes a listed finish from free text" do
    @sku.update!(attribute1: "Chrome,Matte Black")

    assert PhotoSku.new(photo: @photo, sku: @sku, variant_value: "Chrome").variant_in_catalog?
    assert_not PhotoSku.new(photo: @photo, sku: @sku, variant_value: "Antique Bronze").variant_in_catalog?
    assert_not PhotoSku.new(photo: @photo, sku: @sku).variant_in_catalog?
  end

  test "the database rejects a duplicate (photo, sku, variant) even without validations" do
    PhotoSku.create!(photo: @photo, sku: @sku, variant_value: "Chrome")

    assert_raises(ActiveRecord::RecordNotUnique) do
      PhotoSku.new(photo: @photo, sku: @sku, variant_value: "Chrome").save!(validate: false)
    end
  end
end
