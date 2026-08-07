require "test_helper"

module Catalog
  class ModelsSyncerTest < ActiveSupport::TestCase
    setup do
      RoomType.load_vocabulary!
      @community = Community.create!(code: "1682", name: "Bradbury")
    end

    def payload(rooms)
      [ { "model" => "Abigail", "elevation" => "1A", "model_description" => "Abigail 1A",
          "rooms" => rooms } ]
    end

    def photo_named(name)
      photo = Photo.new(name: name)
      photo.image.attach(io: file_fixture("sample.png").open, filename: "sample.png",
        content_type: "image/png")
      photo.save!
      photo
    end

    test "assigns a room type to each synced room" do
      ModelsSyncer.call(@community, payload([
        { "room_code" => "MBATH", "room_desc" => "Master Bath" },
        { "room_code" => "KTI1", "room_desc" => "Kitchen" }
      ]))

      assert_equal "master_bathroom", @community.rooms.find_by(room_code: "MBATH").room_type.key
      assert_equal "kitchen", @community.rooms.find_by(room_code: "KTI1").room_type.key
    end

    test "re-classifies on a later sync when the description changes" do
      ModelsSyncer.call(@community, payload([ { "room_code" => "R1", "room_desc" => "Zone 1" } ]))
      assert_equal "whole_home", @community.rooms.find_by(room_code: "R1").room_type.key

      ModelsSyncer.call(@community, payload([ { "room_code" => "R1", "room_desc" => "Powder Bath" } ]))
      assert_equal "powder_bath", @community.rooms.find_by(room_code: "R1").reload.room_type.key
    end

    # The regression that matters: photos.room_id is ON DELETE SET NULL, so an
    # unguarded prune here silently unassigns rooms from already-tagged photos.
    test "a room referenced by a photo survives a payload that omits it" do
      ModelsSyncer.call(@community, payload([ { "room_code" => "KTI1", "room_desc" => "Kitchen" } ]))
      room = @community.rooms.find_by(room_code: "KTI1")
      photo = photo_named("kitchen")
      photo.update!(community: @community, room: room)

      ModelsSyncer.call(@community, payload([ { "room_code" => "BDR2", "room_desc" => "Bedroom 2" } ]))

      assert Room.exists?(room.id), "the tagged room was pruned"
      assert_equal room.id, photo.reload.room_id, "the photo lost its room"
    end

    test "a room referenced by a lot selection also survives" do
      ModelsSyncer.call(@community, payload([ { "room_code" => "KTI1", "room_desc" => "Kitchen" } ]))
      room = @community.rooms.find_by(room_code: "KTI1")
      lot = Lot.create!(community: @community, lot: "0902")
      LotSelection.create!(lot: lot, room: room, product_code: "AAA", kind: "drawn")

      ModelsSyncer.call(@community, payload([ { "room_code" => "BDR2", "room_desc" => "Bedroom 2" } ]))

      assert Room.exists?(room.id), "a room carrying lot selections was pruned"
    end

    test "an unreferenced room that leaves the catalog is still pruned" do
      ModelsSyncer.call(@community, payload([ { "room_code" => "OLD1", "room_desc" => "Old Room" } ]))
      assert @community.rooms.exists?(room_code: "OLD1")

      ModelsSyncer.call(@community, payload([ { "room_code" => "KTI1", "room_desc" => "Kitchen" } ]))

      assert_not @community.rooms.exists?(room_code: "OLD1")
    end
  end
end
