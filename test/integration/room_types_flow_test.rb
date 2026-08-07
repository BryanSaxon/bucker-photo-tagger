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

  test "an admin can rename a type" do
    sign_in_as(@admin)
    type = RoomType.find_by(key: "outdoor_living")

    patch room_type_path(type), params: { room_type: { name: "Covered Patio" } }

    assert_redirected_to room_types_path
    assert_equal "Covered Patio", type.reload.name
  end

  # ---- Drag to reorder ----

  test "reorder rewrites positions from the submitted sequence" do
    sign_in_as(@admin)
    ids = RoomType.ordered.limit(3).pluck(:id)

    post reorder_room_types_path, params: { ids: ids.reverse.map(&:to_s) }

    assert_response :no_content
    assert_equal ids.reverse, RoomType.where(id: ids).order(:sort_order).pluck(:id)
  end

  test "reorder derives positions rather than trusting a client-sent order value" do
    sign_in_as(@admin)
    first, second = RoomType.ordered.limit(2)

    post reorder_room_types_path, params: { ids: [ second.id.to_s, first.id.to_s ] }

    assert_equal 10, second.reload.sort_order
    assert_equal 20, first.reload.sort_order
  end

  test "reorder ignores ids that do not exist" do
    sign_in_as(@admin)
    real = RoomType.ordered.first

    assert_nothing_raised do
      post reorder_room_types_path, params: { ids: [ "999999", real.id.to_s ] }
    end

    assert_response :no_content
    assert_equal 20, real.reload.sort_order
  end

  test "reorder requires authentication" do
    post reorder_room_types_path, params: { ids: [] }
    assert_redirected_to new_session_path
  end

  test "a new room type is appended to the end of the list" do
    sign_in_as(@admin)
    highest = RoomType.maximum(:sort_order)

    post room_types_path, params: { room_type: { name: "Screened Porch" } }

    assert_equal highest + 10, RoomType.find_by(name: "Screened Porch").sort_order
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
