require "test_helper"

module Skus
  class ImageAttacherTest < ActiveSupport::TestCase
    # Stand-in for Newstart::Client. Serves canned image bytes per filename and
    # records which filenames were requested; a filename listed in `failures`
    # raises like a real download error.
    class FakeClient
      attr_reader :requested

      def initialize(bytes: "\x89PNG-fake-bytes", failures: [])
        @bytes = bytes
        @failures = failures
        @requested = []
      end

      def product_image_file_contents(image_name)
        @requested << image_name
        if @failures.include?(image_name)
          raise Newstart::Client::RequestError, "download failed for #{image_name}"
        end

        Newstart::Client::ImageFile.new(
          body: @bytes, content_type: "image/jpeg", filename: image_name
        )
      end
    end

    def sku(**attrs)
      Sku.create!({ product_code: "AAA", image_filename: "AAA.JPG",
                    image_mimetype: "image/jpeg", image_flag: "BookYesImage" }.merge(attrs))
    end

    test "attaches the stored primary image when no index is supplied" do
      s = sku
      client = FakeClient.new

      attached = Skus::ImageAttacher.call(s, client: client)

      assert_equal 1, attached
      assert s.reload.images_downloaded?
      assert_equal "AAA.JPG", s.images.first.filename.to_s
      assert_equal [ "AAA.JPG" ], client.requested
    end

    test "attaches every live catalog image for the product_code when given the index" do
      s = sku
      images = [
        { "product_code" => "AAA", "filename" => "AAA.JPG", "filemimetype" => "image/jpeg" },
        { "product_code" => "AAA", "filename" => "AAA-black.jpg", "filemimetype" => "image/jpeg" },
        { "product_code" => "AAA", "filename" => "old.jpg", "isarchived" => true },
        { "product_code" => "BBB", "filename" => "other.jpg" }
      ]

      attached = Skus::ImageAttacher.call(s, client: FakeClient.new, images: images)

      assert_equal 2, attached
      names = s.reload.images.map { |i| i.filename.to_s }.sort
      assert_equal [ "AAA-black.jpg", "AAA.JPG" ], names   # archived + other product excluded
    end

    test "is idempotent - re-running does not duplicate attachments" do
      s = sku

      Skus::ImageAttacher.call(s, client: FakeClient.new)
      second = Skus::ImageAttacher.call(s, client: FakeClient.new)

      assert_equal 0, second
      assert_equal 1, s.reload.images.count
    end

    test "returns 0 and attaches nothing when the SKU has no image metadata" do
      s = sku(image_filename: nil, image_flag: "BookNoImage")

      attached = Skus::ImageAttacher.call(s, client: FakeClient.new)

      assert_equal 0, attached
      assert_not s.reload.images_downloaded?
    end

    test "a failed download is skipped and does not abort the others" do
      s = sku
      images = [
        { "product_code" => "AAA", "filename" => "good.jpg" },
        { "product_code" => "AAA", "filename" => "bad.jpg" }
      ]
      client = FakeClient.new(failures: [ "bad.jpg" ])

      attached = Skus::ImageAttacher.call(s, client: client, images: images)

      assert_equal 1, attached
      assert_equal [ "good.jpg" ], s.reload.images.map { |i| i.filename.to_s }
    end

    test "an empty response body is not attached" do
      s = sku
      client = FakeClient.new(bytes: "")

      attached = Skus::ImageAttacher.call(s, client: client)

      assert_equal 0, attached
      assert_not s.reload.images_downloaded?
    end
  end
end
