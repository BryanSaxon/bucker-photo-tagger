require "test_helper"

module Photos
  class DuplicateFinderTest < ActiveSupport::TestCase
    def photo_with(fixture: "sample.png", filename: "a.png")
      photo = Photo.new(name: File.basename(filename, ".*"))
      photo.image.attach(io: file_fixture(fixture).open, filename: filename,
        content_type: "image/png")
      photo.save!
      photo
    end

    def loose_blob(filename: "a.png", fixture: "sample.png")
      ActiveStorage::Blob.create_and_upload!(
        io: file_fixture(fixture).open, filename: filename, content_type: "image/png"
      )
    end

    test "matches a byte-identical image already in the library" do
      existing = photo_with(filename: "kitchen.png")

      assert_equal existing, DuplicateFinder.for_blob(loose_blob(filename: "kitchen-copy.png"))
    end

    test "matches regardless of filename, since the bytes are what matter" do
      existing = photo_with(filename: "IMG_1.png")

      assert_equal existing, DuplicateFinder.for_blob(loose_blob(filename: "totally-different.png"))
    end

    test "does not match different bytes" do
      photo_with(filename: "kitchen.png")

      assert_nil DuplicateFinder.for_blob(loose_blob(fixture: "sample.heic", filename: "other.heic"))
    end

    test "a photo's own blob is not its own duplicate" do
      existing = photo_with(filename: "kitchen.png")

      assert_nil DuplicateFinder.for_blob(existing.image.blob)
    end

    test "returns the oldest match when several copies exist" do
      first = photo_with(filename: "one.png")
      photo_with(filename: "two.png")

      assert_equal first, DuplicateFinder.for_blob(loose_blob(filename: "three.png"))
    end

    test "a blob with no checksum is never a duplicate" do
      photo_with(filename: "kitchen.png")
      blob = loose_blob(filename: "x.png")
      blob.update_columns(checksum: nil)

      assert_nil DuplicateFinder.for_blob(blob)
    end
  end
end
