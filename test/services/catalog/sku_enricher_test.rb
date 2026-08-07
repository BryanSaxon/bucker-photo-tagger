require "test_helper"

module Catalog
  class SkuEnricherTest < ActiveSupport::TestCase
    setup do
      @community = Community.create!(code: "1682", name: "Bradbury")
      @lot = Lot.create!(community: @community, lot: "0902")
      @sold = Sku.create!(product_code: "SOLD1", short_description: "Kitchen Faucet",
        category_code: "04Plumbi", subcategory_code: "81Plumb")
      @unsold = Sku.create!(product_code: "UNSOLD1", short_description: "Never Chosen",
        category_code: "04Plumbi")
    end

    def selection(sku, **attrs)
      LotSelection.create!({ lot: @lot, sku: sku, product_code: sku.product_code,
                             kind: "design" }.merge(attrs))
    end

    test "marks products that appear in a real home's selections as sellable" do
      selection(@sold)

      SkuEnricher.call(fetch_selections: true)

      assert @sold.reload.sellable?
      assert_not @unsold.reload.sellable?
    end

    # The interactive "Refresh SKUs" skips lot selections because it would cost
    # one API call per lot. A run that didn't read them must not conclude the
    # whole catalog is unsold.
    test "leaves sellable untouched when selections were not fetched" do
      @sold.update!(sellable: true)
      @unsold.update!(sellable: true)

      SkuEnricher.call(fetch_selections: false)

      assert @sold.reload.sellable?
      assert @unsold.reload.sellable?
    end

    test "does not blank sellable when the selections table came back empty" do
      @sold.update!(sellable: true)

      SkuEnricher.call(fetch_selections: true) # no selections created

      assert @sold.reload.sellable?
    end

    test "fills in human category names from the selection payload" do
      selection(@sold, category_code: "04Plumbi", category_name: "Plumbing",
        subcategory_code: "81Plumb", subcategory_name: "Faucets")

      SkuEnricher.call(fetch_selections: true)

      @sold.reload
      assert_equal "Plumbing", @sold.category_name
      assert_equal "Faucets", @sold.subcategory_name
    end

    test "a code named anywhere names every sku sharing it" do
      other = Sku.create!(product_code: "OTHER1", short_description: "Another Faucet",
        category_code: "04Plumbi")
      selection(@sold, category_code: "04Plumbi", category_name: "Plumbing")

      SkuEnricher.call(fetch_selections: true)

      assert_equal "Plumbing", other.reload.category_name
    end

    test "falls back to the option payload, which spells the column differently" do
      Option.create!(community: @community, sku: @sold, product_code: @sold.product_code,
        category_code: "04Plumbi", category: "Plumbing From Options")

      SkuEnricher.call(fetch_selections: true)

      assert_equal "Plumbing From Options", @sold.reload.category_name
    end

    test "leaves names alone when neither payload has any" do
      @sold.update!(category_name: "Previously Set")

      SkuEnricher.call(fetch_selections: true)

      assert_equal "Previously Set", @sold.reload.category_name
    end
  end
end
