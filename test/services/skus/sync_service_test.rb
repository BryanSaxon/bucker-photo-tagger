require "test_helper"

module Skus
  class SyncServiceTest < ActiveSupport::TestCase
    # Minimal stand-in for Newstart::Client returning canned products + images.
    FakeClient = Struct.new(:products, :images) do
      def product_library = products
      def product_images = (images || [])
    end

    def products
      [
        { "product_code" => "AAA", "short_description" => "Faucet", "category_code" => "07CabTop",
          "subcategory_code" => "07CabTop", "attribute1_desc" => "Finish**", "attribute1" => "Chrome,Black",
          "image" => "BookYesImage", "lastmoddatetime" => "20260512.120006" },
        { "product_code" => "BBB", "short_description" => "Cabinet", "category_code" => "12Cabs" }
      ]
    end

    def images
      [
        { "product_code" => "AAA", "filename" => "AAA.JPG", "filemimetype" => "image/jpeg",
          "file_id" => "F-1", "source_type" => "Product", "isarchived" => false },
        { "product_code" => "AAA", "filename" => "AAA-black.jpg", "filemimetype" => "image/jpeg",
          "file_id" => "F-2", "source_type" => "ProductAttr", "isarchived" => false },
        { "product_code" => "AAA", "filename" => "old.jpg", "file_id" => "F-3", "isarchived" => true }
      ]
    end

    test "upserts skus and marks the sync completed" do
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new(products, images))

      assert sync.reload.completed?
      assert_equal 2, sync.synced_count
      assert_equal "Faucet", Sku.find_by(product_code: "AAA").short_description
      assert_equal "BookYesImage", Sku.find_by(product_code: "AAA").image_flag
    end

    test "maps image metadata onto skus, preferring the Product image and ignoring archived" do
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new(products, images))

      aaa = Sku.find_by(product_code: "AAA")
      assert aaa.image?
      assert_equal "AAA.JPG", aaa.image_filename          # the source_type: Product one
      assert_equal "image/jpeg", aaa.image_mimetype
      assert_equal "F-1", aaa.image_file_id
      assert_equal 2, aaa.images_count                     # archived one excluded

      bbb = Sku.find_by(product_code: "BBB")
      assert_not bbb.image?
      assert_equal 0, bbb.images_count
    end

    test "image fetch failure does not fail the whole sync" do
      client = FakeClient.new(products, nil)
      def client.product_images = raise(Newstart::Client::RequestError, "images down")
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: client)

      assert sync.reload.completed?
      assert_equal "Faucet", Sku.find_by(product_code: "AAA").short_description
      assert_not Sku.find_by(product_code: "AAA").image?
    end

    test "re-running updates existing skus rather than duplicating" do
      Sku.create!(product_code: "AAA", short_description: "Old")
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new(products, images))

      assert_equal 1, Sku.where(product_code: "AAA").count
      assert_equal "Faucet", Sku.find_by(product_code: "AAA").short_description
    end

    test "records failure when the client raises" do
      failing = Object.new
      def failing.product_library = raise(Newstart::Client::RequestError, "boom")
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: failing)

      assert sync.reload.failed?
      assert_match "boom", sync.error_message
    end
  end
end
