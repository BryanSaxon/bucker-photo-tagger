require "test_helper"

module Photos
  class SaveSelectionsTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @community = Community.create!(name: "Bradbury")
      @floorplan = Floorplan.create!(community: @community, name: "Abigail", elevation: "1A")
      @sku_a = Sku.create!(product_code: "AAA")
      @sku_b = Sku.create!(product_code: "BBB")
      @photo = Photo.new(name: "Kitchen")
      @photo.image.attach(io: file_fixture("sample.png").open, filename: "sample.png", content_type: "image/png")
      @photo.save!
    end

    def call(sku_entries:, community_id: @community.id, floorplan_id: @floorplan.id)
      Photos::SaveSelections.call(
        photo: @photo, community_id: community_id, floorplan_id: floorplan_id,
        sku_entries: sku_entries, user: @user
      )
    end

    test "saves selections, marks complete, records processor" do
      result = call(sku_entries: [ { id: @sku_a.id, pos_x: "0.3", pos_y: "0.4" }, { id: @sku_b.id } ])

      assert result.success?
      @photo.reload
      assert @photo.complete?
      assert_equal @user, @photo.processed_by
      assert_equal [ @sku_a, @sku_b ].map(&:id).sort, @photo.sku_ids.sort

      pinned = @photo.photo_skus.find_by(sku: @sku_a)
      assert_in_delta 0.3, pinned.pos_x
      assert_in_delta 0.4, pinned.pos_y
    end

    test "completes with no placement selected (placement is optional)" do
      result = call(sku_entries: [], community_id: nil, floorplan_id: nil)

      assert result.success?
      @photo.reload
      assert @photo.complete?
      assert_nil @photo.community_id
      assert_nil @photo.floorplan_id
    end

    test "back-fills the community from a lone floorplan" do
      result = call(sku_entries: [], community_id: nil, floorplan_id: @floorplan.id)

      assert result.success?
      assert_equal @community.id, @photo.reload.community_id
    end

    test "reconciles deselected skus on re-save" do
      call(sku_entries: [ { id: @sku_a.id }, { id: @sku_b.id } ])
      call(sku_entries: [ { id: @sku_b.id } ])

      assert_equal [ @sku_b.id ], @photo.reload.sku_ids
    end

    # ---- Variants ----

    test "saves the chosen variant on a tagged sku" do
      call(sku_entries: [ { id: @sku_a.id, variant_value: "Matte Black" } ])

      assert_equal "Matte Black", @photo.reload.photo_skus.sole.variant_value
    end

    test "tags one sku twice under two finishes, each pinned independently" do
      call(sku_entries: [
        { id: @sku_a.id, variant_value: "Matte Black", pos_x: "0.1", pos_y: "0.2" },
        { id: @sku_a.id, variant_value: "Chrome", pos_x: "0.8", pos_y: "0.9" }
      ])

      tags = @photo.reload.photo_skus.order(:variant_value).to_a
      assert_equal 2, tags.size
      assert_equal [ "Chrome", "Matte Black" ], tags.map(&:variant_value)
      assert_in_delta 0.8, tags.first.pos_x
      assert_in_delta 0.1, tags.last.pos_x
    end

    test "reconciles by (sku, variant) so changing a finish replaces that tag" do
      call(sku_entries: [ { id: @sku_a.id, variant_value: "Matte Black" } ])
      call(sku_entries: [ { id: @sku_a.id, variant_value: "Chrome" } ])

      assert_equal [ "Chrome" ], @photo.reload.photo_skus.map(&:variant_value)
    end

    test "removing one finish leaves the other tag intact" do
      call(sku_entries: [
        { id: @sku_a.id, variant_value: "Matte Black" },
        { id: @sku_a.id, variant_value: "Chrome" }
      ])
      call(sku_entries: [ { id: @sku_a.id, variant_value: "Chrome" } ])

      assert_equal [ "Chrome" ], @photo.reload.photo_skus.map(&:variant_value)
    end

    test "accepts a finish the catalog does not list" do
      @sku_a.update!(attribute1: "Chrome,Brushed Nickel", attribute1_desc: "Finish**")
      call(sku_entries: [ { id: @sku_a.id, variant_value: "Antique Bronze" } ])

      tag = @photo.reload.photo_skus.sole
      assert_equal "Antique Bronze", tag.variant_value
      assert_not tag.variant_in_catalog?
    end

    test "a tag saved before variants existed round-trips unchanged" do
      call(sku_entries: [ { id: @sku_a.id, pos_x: "0.5", pos_y: "0.5" } ])
      assert_equal "", @photo.reload.photo_skus.sole.variant_value

      # Re-saving without a variant must neither duplicate nor drop it.
      call(sku_entries: [ { id: @sku_a.id, pos_x: "0.5", pos_y: "0.5" } ])
      assert_equal 1, @photo.reload.photo_skus.count
      assert_in_delta 0.5, @photo.photo_skus.sole.pos_x
    end

    test "variant values arriving with string keys and whitespace are normalized" do
      call(sku_entries: [ { "id" => @sku_a.id, "variant_value" => "  Matte Black  " } ])

      assert_equal "Matte Black", @photo.reload.photo_skus.sole.variant_value
    end
  end
end
