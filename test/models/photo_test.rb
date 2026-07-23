require "test_helper"

class PhotoTest < ActiveSupport::TestCase
  def build_photo(attrs = {})
    photo = Photo.new({ name: "Kitchen" }.merge(attrs))
    photo.image.attach(io: file_fixture("sample.png").open, filename: "sample.png", content_type: "image/png")
    photo
  end

  test "valid with a name and attached image" do
    assert build_photo.valid?
  end

  test "invalid without an image" do
    photo = Photo.new(name: "No image")
    assert_not photo.valid?
    assert_includes photo.errors[:image], "must be attached"
  end

  test "invalid without a name" do
    assert_not build_photo(name: "").valid?
  end

  test "defaults to unprocessed" do
    assert build_photo.unprocessed?
  end

  test "mark_complete! records processor and timestamp" do
    photo = build_photo
    photo.save!
    user = users(:one)

    photo.mark_complete!(user)

    assert photo.complete?
    assert_equal user, photo.processed_by
    assert_not_nil photo.processed_at
  end

  test "search filters by name" do
    a = build_photo(name: "Great Room"); a.save!
    b = build_photo(name: "Primary Bath"); b.save!

    assert_includes Photo.search("room"), a
    assert_not_includes Photo.search("room"), b
  end
end
