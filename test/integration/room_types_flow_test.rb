require "test_helper"

class RoomTypesFlowTest < ActionDispatch::IntegrationTest
  setup do
    RoomType.load_vocabulary!
    @admin = users(:one)
  end

  test "requires authentication" do
    get room_types_path
    assert_redirected_to new_session_path
  end

  test "lists the vocabulary for an admin" do
    sign_in_as(@admin)
    get room_types_path

    assert_response :success
    assert_match "Master Bathroom", @response.body
    assert_match "Powder Bath", @response.body
  end

  test "an admin can add a room type without a deploy" do
    sign_in_as(@admin)

    assert_difference -> { RoomType.count }, 1 do
      post room_types_path, params: { room_type: { name: "Screened Porch", sort_order: 200 } }
    end

    assert_redirected_to room_types_path
    assert_equal "screened_porch", RoomType.last.key
  end

  test "an admin can rename and reorder a type" do
    sign_in_as(@admin)
    type = RoomType.find_by(key: "outdoor_living")

    patch room_type_path(type), params: { room_type: { name: "Covered Patio", sort_order: 5 } }

    assert_redirected_to room_types_path
    type.reload
    assert_equal "Covered Patio", type.name
    assert_equal 5, type.sort_order
  end

  test "hiding a type removes it from the tagging picker but keeps existing photos" do
    sign_in_as(@admin)
    type = RoomType.find_by(key: "basement")

    patch room_type_path(type), params: { room_type: { active: "0" } }

    assert_not type.reload.active?
    assert_not_includes RoomType.available.ordered, type
  end

  # Deleting a type in use would strip the room from photos already tagged
  # with it, so it is deactivated instead.
  test "removing a type that is in use hides it rather than deleting it" do
    sign_in_as(@admin)
    type = RoomType.find_by(key: "kitchen")
    photo = Photo.new(name: "Kitchen", room_type: type)
    photo.image.attach(io: file_fixture("sample.png").open, filename: "sample.png",
      content_type: "image/png")
    photo.save!

    assert_no_difference -> { RoomType.count } do
      delete room_type_path(type)
    end

    assert_not type.reload.active?
    assert_equal type.id, photo.reload.room_type_id
  end

  test "removing an unused type deletes it" do
    sign_in_as(@admin)
    type = RoomType.create!(key: "temp_room", name: "Temp Room")

    assert_difference -> { RoomType.count }, -1 do
      delete room_type_path(type)
    end
  end
end
