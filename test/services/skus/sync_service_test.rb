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

    test "stores every catalog image as a SkuImage keyed to its product" do
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new(products, images))

      aaa = Sku.find_by(product_code: "AAA")
      # Both live images are stored (the archived old.jpg is still recorded, flagged).
      assert_equal 3, aaa.sku_images.count
      primary = aaa.sku_images.find_by(file_id: "F-1")
      assert primary.primary?
      assert_equal "AAA.JPG", primary.filename
      assert_equal "AAA", primary.product_code
      archived = aaa.sku_images.find_by(file_id: "F-3")
      assert archived.archived?
    end

    test "resyncing prunes image records that left the catalog" do
      sync = SkuSync.create!(status: :running)
      Skus::SyncService.call(sync, client: FakeClient.new(products, images))
      assert SkuImage.exists?(file_id: "F-2")

      # Second run: AAA now has only its primary image.
      fewer = [ { "product_code" => "AAA", "filename" => "AAA.JPG", "filemimetype" => "image/jpeg",
                  "file_id" => "F-1", "source_type" => "Product", "isarchived" => false } ]
      Skus::SyncService.call(SkuSync.create!(status: :running), client: FakeClient.new(products, fewer))

      assert SkuImage.exists?(file_id: "F-1")
      assert_not SkuImage.exists?(file_id: "F-2"), "dropped variant should be pruned"
      assert_not SkuImage.exists?(file_id: "F-3")
    end

    test "an empty image payload does not wipe stored image records" do
      Skus::SyncService.call(SkuSync.create!(status: :running), client: FakeClient.new(products, images))
      assert_equal 3, SkuImage.count

      # A run where images come back empty must leave existing records intact.
      Skus::SyncService.call(SkuSync.create!(status: :running), client: FakeClient.new(products, []))
      assert_equal 3, SkuImage.count, "empty image response must not prune records"
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

    test "prunes skus that are no longer in the catalog" do
      Sku.create!(product_code: "STALE", short_description: "Gone from catalog")
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new(products, images))

      assert_nil Sku.find_by(product_code: "STALE")
      assert Sku.find_by(product_code: "AAA")   # still in the catalog
    end

    test "keeps a stale sku that is still tagged in a photo" do
      stale = Sku.create!(product_code: "STALE", short_description: "Tagged but gone")
      photo = Photo.new(name: "Kitchen")
      photo.image.attach(io: file_fixture("sample.png").open, filename: "sample.png", content_type: "image/png")
      photo.save!
      PhotoSku.create!(photo: photo, sku: stale)
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new(products, images))

      assert Sku.find_by(product_code: "STALE"), "referenced sku should be kept"
    end

    test "does not prune when the catalog response is empty" do
      Sku.create!(product_code: "KEEP", short_description: "Existing")
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new([], []))

      assert Sku.find_by(product_code: "KEEP"), "empty response must not wipe the table"
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
