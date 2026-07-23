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

  test "a sku can only be attached to a photo once" do
    PhotoSku.create!(photo: @photo, sku: @sku)
    assert_not PhotoSku.new(photo: @photo, sku: @sku).valid?
  end
end
