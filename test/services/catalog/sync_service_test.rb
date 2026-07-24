require "test_helper"

module Catalog
  class SyncServiceTest < ActiveSupport::TestCase
    # Canned client covering every endpoint the orchestrator touches. `raise_on`
    # lets a test force one endpoint to blow up to check per-community resilience.
    class FakeClient
      def initialize(raise_on: nil)
        @raise_on = raise_on
      end

      def product_library
        [
          { "product_code" => "AAA", "short_description" => "Faucet", "category_code" => "07Cab",
            "subcategory_code" => "81E", "attribute1_desc" => "Finish", "attribute1" => "Chrome",
            "image" => "BookYesImage", "lastmoddatetime" => "20260101.0" },
          { "product_code" => "BBB", "short_description" => "Cabinet" }
        ]
      end

      def product_images
        [ { "product_code" => "AAA", "file_id" => "F-1", "filename" => "aaa.jpg",
            "source_type" => "Product", "isarchived" => false } ]
      end

      def communities
        [ { "project_code" => "1682", "name" => "Bradbury", "product_library_code" => "SIGN" } ]
      end

      def community_models(_pc)
        [
          { "model" => "Abigail", "elevation" => "1A", "model_description" => "Abigail 1A",
            "base_model_price" => "530000", "base_model_rooms" => "kit,mbr", "square_feet" => "2137",
            "bed_count" => "3", "bath_count" => "2", "half_bath_count" => "1", "garage_count" => "2",
            "discontinued" => false, "sellable" => true,
            "rooms" => [ { "room_code" => "KIT", "room_desc" => "Kitchen" },
                         { "room_code" => "MBR", "room_desc" => "Master Bed" } ] },
          { "model" => "Hartley", "elevation" => "2B", "model_description" => "Hartley 2B",
            "sellable" => false, "discontinued" => true,
            "rooms" => [ { "room_code" => "KIT", "room_desc" => "Kitchen" } ] }
        ]
      end

      def community_lots(_pc)
        [
          { "lot" => "0902", "lot_address" => "1 Main", "lot_status" => "Sold", "lot_type" => "Interior",
            "model_description" => "Abigail 1A", "base_model_price" => "530000", "lot_price" => "540000",
            "lot_premium" => "10000", "gross_sale" => "550000", "options" => "20000" },
          { "lot" => "0903", "model_description" => "Unknown Model" }
        ]
      end

      def community_lot(_pc, lot)
        return nil unless lot == "0902"

        { "lot" => "0902",
          "available_rooms" => [ { "room_code" => "KIT", "room_desc" => "Kitchen" } ],
          "selected_drawn_options" => [ { "product_code" => "AAA", "short_description" => "Faucet",
            "unit_price" => "100", "quantity" => "1", "room_code" => "KIT", "room_description" => "Kitchen" } ],
          "selected_design_options" => [ { "product_code" => "ZZZ", "short_description" => "Unknown",
            "unit_price" => "50", "quantity" => "2", "room_code" => "XXX" } ] }
      end

      def community_options(_pc)
        raise Newstart::Client::RequestError, "boom" if @raise_on == :options

        [
          { "product_code" => "AAA", "model" => "Abigail", "elev" => "1A", "model_description" => "Abigail 1A",
            "description" => "Faucet opt", "short_description" => "Faucet", "category" => "Cabinets",
            "category_code" => "07Cab", "subcategory" => "Tops", "subcategory_code" => "81E",
            "option_type" => "OPT", "unit_price" => "100", "qty" => "1", "uofm" => "EA", "gross_sale" => "100",
            "room_replacement_rules" => { "add_rooms" => "bar1", "remove_rooms" => "" }, "moddatetime" => "20260101" },
          { "product_code" => "ZZZ", "model" => "NoModel", "elev" => "9Z" }
        ]
      end

      def community_steps(_pc)
        [ { "step" => "Kitchen", "sortorder" => "1", "area_associations" => "kit",
            "categories" => [ { "category" => "Cabinets", "sortorder" => "1",
              "subcategories" => [ { "subcategory" => "Uppers", "sortorder" => "1" },
                                   { "subcategory" => "Lowers", "sortorder" => "2" } ] } ] } ]
      end
    end

    def sync!(client = FakeClient.new, **opts)
      s = SkuSync.create!(status: :running)
      Catalog::SyncService.call(s, client: client, **opts)
      s.reload
    end

    test "builds the full community graph and records completion" do
      s = sync!

      assert s.completed?
      assert_equal 2, s.synced_count             # product count
      assert_equal 2, Sku.count
      assert_equal 1, SkuImage.count
      assert_equal 1, Community.count
      assert_equal "SIGN", Community.find_by(code: "1682").product_library_code
    end

    test "syncs models (floorplans) with enriched fields and sellable flag" do
      sync!
      c = Community.find_by(code: "1682")

      assert_equal 2, c.floorplans.count
      assert_equal 1, c.floorplans.sellable.count

      abigail = c.floorplans.find_by(name: "Abigail", elevation: "1A")
      assert_equal "Abigail 1A", abigail.model_description
      assert_equal 530000, abigail.base_model_price
      assert_equal 2137, abigail.square_feet
      assert_equal 3, abigail.bed_count
      assert_equal 2, abigail.garage_count
      assert abigail.sellable
      assert_not c.floorplans.find_by(name: "Hartley").sellable
    end

    test "collects the inline room dictionary de-duped per community" do
      sync!
      c = Community.find_by(code: "1682")

      assert_equal %w[KIT MBR], c.rooms.order(:room_code).pluck(:room_code)  # KIT appears on both models, once here
      assert_equal "Kitchen", c.rooms.find_by(room_code: "KIT").room_desc
    end

    test "links lots to models by model_description, leaving unmatched lots unlinked" do
      sync!
      c = Community.find_by(code: "1682")

      matched = c.lots.find_by(lot: "0902")
      assert_equal "Abigail", matched.floorplan.name
      assert_equal 550000, matched.gross_sale
      assert_equal 20000, matched.options_total

      assert_nil c.lots.find_by(lot: "0903").floorplan   # "Unknown Model" doesn't match
    end

    test "stores options resolving sku and model links where possible" do
      sync!
      c = Community.find_by(code: "1682")

      linked = c.options.find_by(product_code: "AAA")
      assert_equal Sku.find_by(product_code: "AAA"), linked.sku
      assert_equal "Abigail", linked.floorplan.name
      assert_equal [ "bar1" ], linked.add_room_codes

      unlinked = c.options.find_by(product_code: "ZZZ")
      assert_nil unlinked.sku
      assert_nil unlinked.floorplan
    end

    test "stores the configurator step tree" do
      sync!
      c = Community.find_by(code: "1682")

      step = c.steps.sole
      assert_equal "Kitchen", step.step
      cat = step.step_categories.sole
      assert_equal "Cabinets", cat.name
      assert_equal %w[Uppers Lowers], cat.step_subcategories.ordered.pluck(:name)
    end

    test "stores per-lot selections resolving sku and room best-effort" do
      sync!
      c = Community.find_by(code: "1682")
      lot = c.lots.find_by(lot: "0902")

      assert_equal 2, lot.lot_selections.count
      drawn = lot.lot_selections.drawn.sole
      assert_equal "AAA", drawn.product_code
      assert_equal Sku.find_by(product_code: "AAA"), drawn.sku
      assert_equal "KIT", drawn.room.room_code

      design = lot.lot_selections.design.sole
      assert_nil design.sku          # ZZZ not a known product
      assert_nil design.room         # XXX not a known room

      assert_equal 0, c.lots.find_by(lot: "0903").lot_selections.count  # detail returns nil
    end

    test "lot_limit caps how many lots get selection detail" do
      sync!(FakeClient.new, lot_limit: 0)
      assert_equal 0, LotSelection.count
    end

    test "fetch_selections false skips lot detail entirely" do
      sync!(FakeClient.new, fetch_selections: false)
      assert_equal 0, LotSelection.count
      assert_equal 2, Community.find_by(code: "1682").lots.count  # lots still synced
    end

    test "a failing community sub-endpoint does not abort the whole sync" do
      s = sync!(FakeClient.new(raise_on: :options))

      assert s.completed?                                   # overall run still completes
      c = Community.find_by(code: "1682")
      assert_equal 2, c.floorplans.count                    # models synced before the failure
      assert_equal 0, c.options.count                       # options failed and were skipped
    end

    test "re-running is idempotent" do
      sync!
      sync!
      c = Community.find_by(code: "1682")

      assert_equal 2, c.floorplans.count
      assert_equal 2, c.rooms.count
      assert_equal 2, c.lots.count
      assert_equal 2, c.options.count
      assert_equal 1, c.steps.count
    end
  end
end
