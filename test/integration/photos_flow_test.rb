require "test_helper"

class PhotosFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @community = Community.create!(name: "Bradbury")
    @floorplan = Floorplan.create!(community: @community, name: "Abigail", elevation: "1A")
    @sku = Sku.create!(product_code: "AAA", short_description: "Faucet")
  end

  def create_photo(name:, status: :unprocessed)
    photo = Photo.new(name: name, status: status)
    photo.image.attach(io: file_fixture("sample.png").open, filename: "sample.png", content_type: "image/png")
    photo.save!
    photo
  end

  test "index requires authentication" do
    get photos_path
    assert_redirected_to new_session_path
  end

  test "index shows unprocessed by default and completed via toggle" do
    todo = create_photo(name: "Needs work")
    done = create_photo(name: "All done", status: :complete)
    sign_in_as(@user)

    get photos_path
    assert_response :success
    assert_match "Needs work", @response.body
    assert_no_match "All done", @response.body

    get photos_path(status: "complete")
    assert_match "All done", @response.body
  end

  test "search filters the index by name" do
    create_photo(name: "Great Room")
    create_photo(name: "Primary Bath")
    sign_in_as(@user)

    get photos_path(q: "room")
    assert_match "Great Room", @response.body
    assert_no_match "Primary Bath", @response.body
  end

  test "uploads multiple photos as unprocessed" do
    sign_in_as(@user)
    files = [
      fixture_file_upload("sample.png", "image/png"),
      fixture_file_upload("sample.png", "image/png")
    ]

    assert_difference -> { Photo.count }, 2 do
      post photos_path, params: { photo: { images: files } }
    end
    assert_redirected_to photos_path
    assert Photo.all.all?(&:unprocessed?)
  end

  test "saving selections marks the photo complete" do
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: {
      community_id: @community.id, floorplan_id: @floorplan.id,
      skus: [ { id: @sku.id, pos_x: "0.5", pos_y: "0.5" } ]
    } }

    assert_redirected_to photos_path
    photo.reload
    assert photo.complete?
    assert_equal @user, photo.processed_by
    assert_equal [ @sku.id ], photo.sku_ids
  end

  test "saving completes the photo even with no placement selected" do
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: { community_id: "", floorplan_id: "", room_id: "", skus: [] } }

    assert_redirected_to photos_path
    photo.reload
    assert photo.complete?
    assert_nil photo.community_id
    assert_nil photo.floorplan_id
  end

  test "saving with only a floorplan back-fills its community" do
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: { floorplan_id: @floorplan.id, skus: [] } }

    assert_redirected_to photos_path
    assert_equal @community.id, photo.reload.community_id
  end

  test "sku_search returns matching results" do
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    get sku_search_photo_path(photo, q: "faucet")
    assert_response :success
    assert_match "AAA", @response.body
  end

  test "the new upload page renders the cascading location selects" do
    sign_in_as(@user)
    get new_photo_path
    assert_response :success
    assert_select "select#photo_community_id"
    assert_select "select#photo_floorplan_id"
    assert_select "select#photo_room_id"
  end

  test "uploading with a location stamps it on every created photo" do
    room = @community.rooms.create!(room_code: "KIT", room_desc: "Kitchen")
    sign_in_as(@user)
    files = [ fixture_file_upload("sample.png", "image/png"), fixture_file_upload("sample.png", "image/png") ]

    assert_difference -> { Photo.count }, 2 do
      post photos_path, params: { photo: {
        images: files, community_id: @community.id, floorplan_id: @floorplan.id, room_id: room.id
      } }
    end
    assert_redirected_to photos_path
    assert Photo.all.all? { |p| p.community_id == @community.id && p.floorplan_id == @floorplan.id && p.room_id == room.id }
  end

  test "saving selections persists the chosen room" do
    room = @community.rooms.create!(room_code: "KIT", room_desc: "Kitchen")
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: {
      community_id: @community.id, floorplan_id: @floorplan.id, room_id: room.id, skus: []
    } }

    assert_redirected_to photos_path
    assert_equal room.id, photo.reload.room_id
  end

  test "scoped sku_search narrows to products available for the photo's context" do
    elsewhere = Sku.create!(product_code: "ZZZ", short_description: "Faucet elsewhere")
    Option.create!(community: @community, sku: @sku, product_code: @sku.product_code) # AAA available here; ZZZ not
    photo = create_photo(name: "Kitchen")
    photo.update!(community: @community)
    sign_in_as(@user)

    get sku_search_photo_path(photo, q: "faucet", scoped: "1")
    assert_response :success
    assert_match "AAA", @response.body
    assert_no_match "ZZZ", @response.body

    get sku_search_photo_path(photo, q: "faucet") # unscoped shows both
    assert_match "ZZZ", @response.body
    assert_equal elsewhere.product_code, "ZZZ"
  end
end
