require "test_helper"

module Rooms
  class ClassifierTest < ActiveSupport::TestCase
    def key(code, desc = nil) = Classifier.key_for(code, desc)

    # Ordering is the thing that breaks silently here: if a generic rule runs
    # first, every master bath quietly files as a secondary one.
    test "master beats the generic bath and bed rules" do
      assert_equal :master_bathroom, key("MBATH", "Master Bath")
      assert_equal :master_bathroom, key("OWNBTH", "Owner's Bath")
      assert_equal :master_bathroom, key("PRIMBATH", "Primary Bathroom")
      assert_equal :master_bedroom, key("MBED", "Master Bedroom")
      assert_equal :master_bedroom, key("OWNBED", "Owner's Suite")
      assert_equal :master_bedroom, key("PRIMBDRM", "Primary Bedroom")
    end

    test "powder beats every bath rule" do
      assert_equal :powder_bath, key("POWDER", "Powder Bath")
      assert_equal :powder_bath, key("PWDR", "Powder Room")
      assert_equal :powder_bath, key("HALFBATH", "Half Bath")
    end

    test "unqualified bed and bath fall through to secondary" do
      assert_equal :secondary_bathroom, key("BTR2", "Bath 2")
      assert_equal :secondary_bathroom, key("BATH3", "Bathroom 3")
      assert_equal :secondary_bedroom, key("BDR3", "Bedroom 3")
      assert_equal :secondary_bedroom, key("BDC2", "Bed 2")
    end

    test "rooms whose names merely contain bath or bed are not bathrooms" do
      assert_equal :laundry, key("LAUN1", "Laundry")
      assert_equal :mudroom, key("MUD1", "Mud Room")
    end

    test "classifies the common living spaces" do
      assert_equal :kitchen, key("KTI1", "Kitchen")
      assert_equal :dining_room, key("DIN1", "Dining Room")
      assert_equal :living_room, key("GRT1", "Great Room")
      assert_equal :living_room, key("FAM1", "Family Room")
      assert_equal :den, key("DEN1", "Den")
      assert_equal :loft, key("LFT1", "Loft")
      assert_equal :game_room, key("BON1", "Bonus Room")
      assert_equal :office, key("OFF1", "Study")
      assert_equal :garage, key("XGAR1", "Garage")
      assert_equal :basement, key("BSMT", "Basement")
      assert_equal :outdoor_living, key("PAT1", "Covered Patio")
      assert_equal :outdoor_living, key("PRCH", "Screened Porch")
      assert_equal :exterior, key("EXTR", "Exterior")
    end

    # Real labels from Signature's 226-entry dictionary that the first pass got
    # wrong: a location qualifier was beating the room noun.
    test "the room noun wins over a location qualifier" do
      assert_equal :secondary_bedroom, key(nil, "Bed Over Garage OPT")
      assert_equal :secondary_bathroom, key(nil, "Bath Over Garage OPT")
      assert_equal :secondary_bedroom, key(nil, "Bed Finished Basement OPT")
      assert_equal :secondary_bathroom, key(nil, "Bath Finished Base Linen")
      # …but a plain garage or basement is still itself.
      assert_equal :garage, key("XGAR1", "Garage")
      assert_equal :basement, key("BSMT", "Finished Basement")
    end

    test "matches the full words, not just the abbreviations" do
      assert_equal :secondary_bedroom, key(nil, "Bedroom Suite")
      assert_equal :secondary_bathroom, key(nil, "Bathroom 3")
    end

    test "a closet is a closet whatever it hangs off" do
      assert_equal :closet, key("BDC11", "Primary Bed WIC 2")
      assert_equal :closet, key(nil, "Foyer Closet")
      assert_equal :closet, key(nil, "Stair Hall Closet")
      assert_equal :closet, key(nil, "Flex Closet")
    end

    test "a water closet is a toilet room, not storage" do
      assert_equal :powder_bath, key("WC1", "Water Closet")
    end

    test "classifies the circulation and service spaces" do
      assert_equal :entry, key(nil, "Foyer OPT")
      assert_equal :entry, key(nil, "Front Stoop")
      assert_equal :hallway, key(nil, "Stair Hall")
      assert_equal :hallway, key(nil, "Gallery")
      assert_equal :pantry, key(nil, "Chef's Pantry w/ Cab Stack")
      assert_equal :kitchen, key(nil, "Kitchenette")
    end

    test "catalog entries that are not a room land in whole_home" do
      assert_equal :whole_home, key(nil, "Interior of home")
      assert_equal :whole_home, key(nil, "Included Hardwood Areas OPT")
      assert_equal :whole_home, key(nil, "Drawn Options")
    end

    # The fallback must not be a room designers actually choose, or the
    # unclassifiable quietly pollute a real category.
    test "an unrecognized code lands in the fallback, which is not a real room" do
      assert_equal :whole_home, key("ZZQ9", "Zone 9")
      assert_equal :whole_home, key(nil, nil)
      assert_not_equal :flex_room, Classifier::FALLBACK
      assert_equal :flex_room, key(nil, "Flex 2")
    end

    test "matches on the code alone when no description is given" do
      assert_equal :kitchen, key("KITCHEN")
      assert_equal :master_bathroom, key(nil, "Master Bath")
    end

    test "room_type_id_for resolves against the seeded vocabulary" do
      RoomType.load_vocabulary!
      expected = RoomType.find_by(key: "master_bathroom").id

      assert_equal expected, Classifier.room_type_id_for("MBATH", "Master Bath")
    end

    test "every rule and the fallback map to a real room type" do
      RoomType.load_vocabulary!
      keys = (Classifier::RULES.map(&:first) + [ Classifier::FALLBACK ]).uniq.map(&:to_s)

      assert_empty keys - RoomType.pluck(:key),
        "classifier references room types that config/room_types.yml doesn't define"
    end
  end
end
