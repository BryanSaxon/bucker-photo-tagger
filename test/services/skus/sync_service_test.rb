require "test_helper"

module Skus
  class SyncServiceTest < ActiveSupport::TestCase
    # Minimal stand-in for Newstart::Client returning canned products.
    FakeClient = Struct.new(:products) do
      def product_library = products
    end

    def products
      [
        { "product_code" => "AAA", "short_description" => "Faucet", "category_code" => "07CabTop",
          "subcategory_code" => "07CabTop", "attribute1_desc" => "Finish**", "attribute1" => "Chrome,Black",
          "image" => "BookYesImage", "lastmoddatetime" => "20260512.120006" },
        { "product_code" => "BBB", "short_description" => "Cabinet", "category_code" => "12Cabs" }
      ]
    end

    test "upserts skus and marks the sync completed" do
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new(products))

      assert sync.reload.completed?
      assert_equal 2, sync.synced_count
      assert_equal "Faucet", Sku.find_by(product_code: "AAA").short_description
      assert_equal "BookYesImage", Sku.find_by(product_code: "AAA").image_flag
    end

    test "re-running updates existing skus rather than duplicating" do
      Sku.create!(product_code: "AAA", short_description: "Old")
      sync = SkuSync.create!(status: :running)

      Skus::SyncService.call(sync, client: FakeClient.new(products))

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
