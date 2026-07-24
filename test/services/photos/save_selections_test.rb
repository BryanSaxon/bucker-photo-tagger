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
  end
end
