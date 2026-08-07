require "test_helper"

class PhotosFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @community = Community.create!(name: "Bradbury")
    @floorplan = Floorplan.create!(community: @community, name: "Abigail", elevation: "1A")
    @sku = Sku.create!(product_code: "AAA", short_description: "Faucet")
  end

  # Distinct bytes per name: uploading the same fixture twice is now correctly
  # treated as re-uploading one photo, not adding two.
  def distinct_upload(name)
    digest = Digest::MD5.hexdigest(name)
    path = Rails.root.join("tmp", "test-image-#{digest}.png")
    unless path.exist?
      seed = digest.to_i(16)
      FileUtils.mkdir_p(path.dirname)
      Vips::Image.black(8 + (seed % 24), 8 + ((seed >> 16) % 24)).write_to_file(path.to_s)
    end
    Rack::Test::UploadedFile.new(path.to_s, "image/png", original_filename: name)
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
    files = [ distinct_upload("one.png"), distinct_upload("two.png") ]

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
    RoomType.load_vocabulary!
    @community.rooms.create!(room_code: "KIT", room_desc: "Kitchen")
    sign_in_as(@user)

    get new_photo_path

    assert_response :success
    assert_select "select#photo_community_id"
    assert_select "select#photo_floorplan_id"
    assert_select "select#photo_room_type_id"
    # The catalog-code refinement, shown because this community has synced rooms.
    assert_select "select#photo_room_id"
  end

  test "the upload page hides the catalog room refinement when none are synced" do
    RoomType.load_vocabulary!
    sign_in_as(@user)

    get new_photo_path

    assert_response :success
    assert_select "select#photo_room_type_id"
    assert_select "select#photo_room_id", count: 0
  end

  test "uploading with a location stamps it on every created photo" do
    room = @community.rooms.create!(room_code: "KIT", room_desc: "Kitchen")
    sign_in_as(@user)
    files = [ distinct_upload("three.png"), distinct_upload("four.png") ]

    assert_difference -> { Photo.count }, 2 do
      post photos_path, params: { photo: {
        images: files, community_id: @community.id, floorplan_id: @floorplan.id, room_id: room.id
      } }
    end
    assert_redirected_to photos_path
    assert Photo.all.all? { |p| p.community_id == @community.id && p.floorplan_id == @floorplan.id && p.room_id == room.id }
  end

  test "uploading via direct-upload signed_ids creates photos" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("sample.png").open, filename: "direct.png", content_type: "image/png"
    )
    sign_in_as(@user)

    assert_difference -> { Photo.count }, 1 do
      post photos_path, params: { photo: { signed_ids: [ blob.signed_id ], community_id: @community.id } }
    end
    assert_redirected_to photos_path
    created = Photo.order(:created_at).last
    assert_equal blob, created.image.blob
    assert_equal @community.id, created.community_id
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

  # ---- Re-upload ----

  test "re-uploading a photo applies the new location instead of adding a copy" do
    sign_in_as(@user)
    post photos_path, params: { photo: { images: [ distinct_upload("album.png") ] } }
    original = Photo.order(:created_at).last
    assert_nil original.community_id

    assert_no_difference -> { Photo.count } do
      post photos_path, params: { photo: {
        images: [ distinct_upload("album.png") ],
        community_id: @community.id, floorplan_id: @floorplan.id
      } }
    end

    assert_redirected_to photos_path
    assert_match(/placement updated/, flash[:notice])
    original.reload
    assert_equal @community.id, original.community_id
    assert_equal @floorplan.id, original.floorplan_id
  end

  test "unchecking the update option keeps a deliberate second copy" do
    sign_in_as(@user)
    post photos_path, params: { photo: { images: [ distinct_upload("album2.png") ] } }

    assert_difference -> { Photo.count }, 1 do
      post photos_path, params: { photo: {
        images: [ distinct_upload("album2.png") ], update_existing: "0"
      } }
    end
  end

  # ---- Search tabs ----

  test "tab counts reflect the active search rather than library totals" do
    create_photo(name: "kitchen-one")
    create_photo(name: "kitchen-two", status: :complete)
    create_photo(name: "unrelated-bathroom", status: :complete)
    sign_in_as(@user)

    get photos_path(q: "kitchen")

    assert_response :success
    # 1 unprocessed and 1 completed match — not the library totals of 1 and 2.
    assert_select ".segmented__item", text: /Needs processing\s*1/
    assert_select ".segmented__item", text: /Completed\s*1/
  end

  test "an empty search offers the matches waiting on the other tab" do
    create_photo(name: "only-completed-match", status: :complete)
    sign_in_as(@user)

    get photos_path(q: "only-completed")

    assert_response :success
    assert_match "No unprocessed photos match", @response.body
    # Without this link the photo looks like it isn't in the system at all.
    assert_select ".empty-state a[href=?]",
      photos_path(q: "only-completed", status: "complete"), text: "1 match"
  end

  test "no cross-tab link is offered when nothing matches anywhere" do
    create_photo(name: "kitchen")
    sign_in_as(@user)

    get photos_path(q: "nothing-matches-this")

    assert_response :success
    assert_select ".empty-state a", count: 0
  end

  # ---- Grouping vs existing tags ----

  # Tags made before grouping existed sit on whichever line item was picked,
  # which may not be the representative the picker now shows. Comparing sku ids
  # would offer that same product again as though it were untagged.
  test "a tag on a non-representative sku still marks its group as selected" do
    rep = Sku.create!(product_code: "CAB1", short_description: "Arbor Painted",
      category_code: "07CabTop", subcategory_code: "12Cabs")
    sibling = Sku.create!(product_code: "CAB2", short_description: "Arbor Painted",
      category_code: "07CabTop", subcategory_code: "12Cabs")
    photo = create_photo(name: "Kitchen")
    PhotoSku.create!(photo: photo, sku: sibling) # the older, non-representative tag
    sign_in_as(@user)

    get sku_search_photo_path(photo, q: "arbor")

    assert_response :success
    assert_select "button.sku-result[data-sku-id=?][disabled]", rep.id.to_s
  end

  test "an existing tag on a now-untaggable sku still renders on the photo" do
    junk = Sku.create!(product_code: "OLD1", short_description: "Hood Insert",
      category_code: "99Unsell")
    photo = create_photo(name: "Kitchen")
    PhotoSku.create!(photo: photo, sku: junk, pos_x: 0.3, pos_y: 0.3)
    sign_in_as(@user)

    get photo_path(photo)

    assert_response :success
    # Filtered out of the picker, but the tag itself is never hidden or lost.
    assert_match "Hood Insert", @response.body
    assert_not_includes Sku.taggable, junk
  end

  # ---- Room types ----

  test "saving persists the chosen room type" do
    RoomType.load_vocabulary!
    kitchen = RoomType.find_by(key: "kitchen")
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: { room_type_id: kitchen.id, skus: [] } }

    assert_redirected_to photos_path
    assert_equal kitchen.id, photo.reload.room_type_id
  end

  test "choosing only a specific catalog room derives its room type" do
    RoomType.load_vocabulary!
    room = @community.rooms.create!(room_code: "MBATH", room_desc: "Master Bath",
      room_type: RoomType.find_by(key: "master_bathroom"))
    photo = create_photo(name: "Bath")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: { room_id: room.id, skus: [] } }

    assert_redirected_to photos_path
    assert_equal "master_bathroom", photo.reload.room_type.key
  end

  test "the room picker is populated even with no catalog rooms synced" do
    RoomType.load_vocabulary!
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    get photo_path(photo)

    assert_response :success
    assert_select "select[name=?]", "photo[room_type_id]"
    assert_select "option", text: "Master Bathroom"
    # No catalog rooms exist, so the refinement is hidden rather than empty.
    assert_select "select[name=?]", "photo[room_id]", count: 0
  end

  # ---- Variants ----

  test "saving selections persists the chosen finish" do
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: {
      community_id: @community.id,
      skus: [ { id: @sku.id, variant_value: "Matte Black", pos_x: "0.4", pos_y: "0.6" } ]
    } }

    assert_redirected_to photos_path
    tag = photo.reload.photo_skus.sole
    assert_equal "Matte Black", tag.variant_value
    assert_in_delta 0.4, tag.pos_x
  end

  test "one product can be tagged twice in a photo under two finishes" do
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: {
      skus: [
        { id: @sku.id, variant_value: "Matte Black", pos_x: "0.1", pos_y: "0.1" },
        { id: @sku.id, variant_value: "Chrome", pos_x: "0.9", pos_y: "0.9" }
      ]
    } }

    assert_redirected_to photos_path
    assert_equal [ "Chrome", "Matte Black" ], photo.reload.photo_skus.map(&:variant_value).sort
  end

  test "the processing screen renders a finish picker only for products with choices" do
    plain = Sku.create!(product_code: "PLAIN", short_description: "Plain Item")
    varied = Sku.create!(product_code: "VAR", short_description: "Varied Item",
      attribute1_desc: "Finish**", attribute1: "Chrome,Matte Black")
    photo = create_photo(name: "Kitchen")
    PhotoSku.create!(photo: photo, sku: plain)
    PhotoSku.create!(photo: photo, sku: varied, variant_value: "Chrome")
    sign_in_as(@user)

    get photo_path(photo)
    assert_response :success
    assert_select "select[data-role=?]", "variant-select", count: 1
    assert_select "option[value=?]", "Matte Black"
    # The "**" required-marker is a source-catalog artifact, not a label.
    assert_no_match(/Finish\*\*/, @response.body)
  end

  test "selected_sku_row renders a row carrying the product's finish options" do
    varied = Sku.create!(product_code: "VAR2", short_description: "Varied",
      attribute1_desc: "Color**", attribute1: "White,Black")
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    get selected_sku_row_photo_path(photo, sku_id: varied.id)
    assert_response :success
    assert_select "option[value=?]", "White"
    assert_select "option[value=?]", "__other__"
    assert_select "input[name=?]", "photo[skus][][id]"
  end

  test "a product without finishes still submits a variant_value key" do
    plain = Sku.create!(product_code: "PLAIN2", short_description: "Plain")
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    get selected_sku_row_photo_path(photo, sku_id: plain.id)
    assert_response :success
    # Rails groups photo[skus][][…] by repeating key, so every row must carry
    # the same key set or values merge across rows.
    assert_select "input[type=hidden][name=?]", "photo[skus][][variant_value]"
  end

  test "the needs-a-finish queue lists only completed photos missing a recorded finish" do
    varied = Sku.create!(product_code: "VAR3", attribute1: "Chrome,Matte Black")

    needs = create_photo(name: "Needs a finish", status: :complete)
    PhotoSku.create!(photo: needs, sku: varied) # choices exist, none recorded

    done = create_photo(name: "Already finished", status: :complete)
    PhotoSku.create!(photo: done, sku: varied, variant_value: "Chrome")

    plain = create_photo(name: "No choices to make", status: :complete)
    PhotoSku.create!(photo: plain, sku: @sku) # product has no finish options

    sign_in_as(@user)
    get photos_path(status: "complete", filter: "missing_variants")

    assert_response :success
    assert_match "Needs a finish", @response.body
    assert_no_match "Already finished", @response.body
    assert_no_match "No choices to make", @response.body
  end

  test "unpermitted sku keys are dropped rather than assigned" do
    photo = create_photo(name: "Kitchen")
    sign_in_as(@user)

    patch photo_path(photo), params: { photo: {
      skus: [ { id: @sku.id, variant_value: "Chrome", pos_x: "0.5", pos_y: "0.5", sku_id: 999 } ]
    } }

    assert_redirected_to photos_path
    tag = photo.reload.photo_skus.sole
    assert_equal "Chrome", tag.variant_value
    assert_equal @sku.id, tag.sku_id
  end
end
