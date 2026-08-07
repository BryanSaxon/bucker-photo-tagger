require "test_helper"
require "zip"

module Photos
  class BatchUploadTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    def image_upload(name = "sample.png", type = "image/png")
      Rack::Test::UploadedFile.new(image_path_for(name), type, original_filename: name)
    end

    # Image bytes are derived from the filename, so two uploads sharing a name
    # are byte-identical (what the re-upload tests need) while two with
    # different names are not (what the batch tests need). Uploading the one
    # fixture repeatedly would now read as a re-upload of the same photo.
    def image_path_for(name)
      digest = Digest::MD5.hexdigest(name)
      path = Rails.root.join("tmp", "test-image-#{digest}.png")
      unless path.exist?
        seed = digest.to_i(16)
        FileUtils.mkdir_p(path.dirname)
        Vips::Image.black(8 + (seed % 24), 8 + ((seed >> 16) % 24)).write_to_file(path.to_s)
      end
      path.to_s
    end

    def sample_path
      file_fixture("sample.png").to_s
    end

    # Builds a real .zip UploadedFile containing the given entries
    # ({ "entry/name.png" => source_path }).
    def zip_upload(entries, filename = "batch.zip")
      tmp = Tempfile.new([ "batch", ".zip" ])
      tmp.close
      File.delete(tmp.path)
      Zip::File.open(tmp.path, create: true) do |zip|
        entries.each { |entry_name, src| zip.add(entry_name, src) }
      end
      Rack::Test::UploadedFile.new(tmp.path, "application/zip", original_filename: filename)
    end

    test "creates an unprocessed photo per image file with the image attached" do
      result = BatchUpload.call(files: [ image_upload("kitchen.png"), image_upload("bath.png") ])

      assert result.success?
      assert_equal 2, result.count
      assert result.created.all?(&:persisted?)
      assert result.created.all? { |p| p.image.attached? }
      assert result.created.all?(&:unprocessed?)
      assert_equal %w[bath kitchen], result.created.map(&:name).sort
    end

    test "expands a zip into a photo per contained image, skipping junk entries" do
      zip = zip_upload(
        "photos/one.png" => image_path_for("one.png"),
        "photos/two.jpg" => image_path_for("two.jpg"),
        "photos/readme.txt" => sample_path,        # non-image, skipped
        "__MACOSX/._one.png" => sample_path,       # mac junk, skipped
        ".hidden.png" => sample_path               # dotfile, skipped
      )

      result = BatchUpload.call(files: [ zip ])

      assert result.success?, result.errors.inspect
      assert_equal 2, result.count
      assert_equal %w[one two], result.created.map(&:name).sort
      assert result.created.all? { |p| p.image.attached? }
    end

    test "mixes loose images and zips in one batch" do
      zip = zip_upload("z/a.png" => image_path_for("a.png"))
      result = BatchUpload.call(files: [ image_upload("loose.png"), zip ])

      assert_equal 2, result.count
    end

    test "stamps the chosen community, floorplan and room on every photo" do
      community = Community.create!(code: "1682", name: "Bradbury")
      floorplan = community.floorplans.create!(name: "Abigail", elevation: "1A")
      room = community.rooms.create!(room_code: "KIT", room_desc: "Kitchen")

      result = BatchUpload.call(files: [ image_upload, image_upload("b.png") ],
        community_id: community.id, floorplan_id: floorplan.id, room_id: room.id)

      assert_equal 2, result.count
      assert result.created.all? { |p| p.community_id == community.id }
      assert result.created.all? { |p| p.floorplan_id == floorplan.id }
      assert result.created.all? { |p| p.room_id == room.id }
    end

    test "back-fills community from a lone floorplan" do
      community = Community.create!(code: "1682", name: "Bradbury")
      floorplan = community.floorplans.create!(name: "Abigail", elevation: "1A")

      result = BatchUpload.call(files: [ image_upload ], floorplan_id: floorplan.id)

      assert_equal community.id, result.created.first.community_id
    end

    test "rejects an inconsistent community/plan combination without creating photos" do
      community = Community.create!(code: "1682", name: "Bradbury")
      other = Community.create!(code: "1760", name: "Mills Creek")
      floorplan = other.floorplans.create!(name: "Delmar", elevation: "1A")

      result = BatchUpload.call(files: [ image_upload ],
        community_id: community.id, floorplan_id: floorplan.id)

      assert_not result.success?
      assert_equal 0, result.count
      assert_equal 0, Photo.count
      assert_match(/not in the selected community/, result.errors.to_sentence)
    end

    def blob(filename = "direct.png")
      ActiveStorage::Blob.create_and_upload!(
        io: File.open(image_path_for(filename)), filename: filename, content_type: "image/png"
      )
    end

    test "attaches images uploaded via signed_ids without re-uploading bytes" do
      b = blob("kitchen.png")
      result = BatchUpload.call(signed_ids: [ b.signed_id ])

      assert_equal 1, result.count
      photo = result.created.first
      assert photo.image.attached?
      assert_equal b, photo.image.blob
      assert_equal "kitchen", photo.name
    end

    test "mixes direct-uploaded images (signed_ids) and a zip in one submit" do
      zip = zip_upload("z/a.png" => image_path_for("a.png"))
      result = BatchUpload.call(signed_ids: [ blob.signed_id ], files: [ zip ])

      assert_equal 2, result.count
    end

    test "stamps context onto direct-uploaded photos too" do
      community = Community.create!(code: "1682", name: "Bradbury")
      result = BatchUpload.call(signed_ids: [ blob.signed_id ], community_id: community.id)

      assert_equal community.id, result.created.first.community_id
    end

    # Pin the HEIC capability probe so both branches are exercised regardless of
    # whether the machine running the suite has libheif.
    def with_heic_decoding(available)
      Photos::ImageSupport.instance_variable_set(:@heic_available, available)
      yield
    ensure
      Photos::ImageSupport.reset!
    end

    def heic_blob(filename = "IMG_0042.HEIC")
      ActiveStorage::Blob.create_and_upload!(
        io: file_fixture("sample.heic").open, filename: filename, content_type: "image/heic"
      )
    end

    # Where libvips can't decode HEIF, accepting the file would create a Photo
    # whose thumbnail then fails invisibly — reject it with guidance instead.
    test "a HEIC upload is rejected with guidance when decoding is unavailable" do
      with_heic_decoding(false) do
        blob = heic_blob

        assert_no_difference -> { Photo.count } do
          result = BatchUpload.call(signed_ids: [ blob.signed_id ])

          assert_equal 0, result.count
          assert_not result.success?
          assert_match(/HEIC photos aren’t supported yet/, result.errors.to_sentence)
          assert_match(/Most Compatible/, result.errors.to_sentence)
        end
      end
    end

    test "a HEIC upload is accepted when decoding is available" do
      with_heic_decoding(true) do
        result = BatchUpload.call(signed_ids: [ heic_blob.signed_id ])

        assert_equal 1, result.count
        assert result.created.first.image.attached?
      end
    end

    test "a rejected direct upload purges its blob rather than paying storage for it" do
      with_heic_decoding(false) do
        blob = heic_blob("IMG_0043.heic")

        perform_enqueued_jobs { BatchUpload.call(signed_ids: [ blob.signed_id ]) }

        assert_not ActiveStorage::Blob.exists?(blob.id)
      end
    end

    test "a non-image direct upload gets the generic unsupported message" do
      txt = ActiveStorage::Blob.create_and_upload!(
        io: file_fixture("sample.png").open, filename: "notes.txt", content_type: "text/plain"
      )
      result = BatchUpload.call(signed_ids: [ txt.signed_id ])

      assert_equal 0, result.count
      assert_match(/unsupported file type/, result.errors.to_sentence)
    end

    # ---- Re-upload updates placement ----
    #
    # Kassie's actual request: her phone albums are already organised by
    # community and floorplan, so re-uploading should carry that placement onto
    # photos already in the library rather than warn about duplicates.

    def existing_photo(filename: "kitchen.png")
      result = BatchUpload.call(files: [ image_upload(filename) ])
      result.created.first
    end

    test "a re-upload updates the existing photo's placement instead of duplicating it" do
      community = Community.create!(code: "1682", name: "Bradbury")
      floorplan = community.floorplans.create!(name: "Abigail", elevation: "1A")
      existing = existing_photo

      assert_no_difference -> { Photo.count } do
        result = BatchUpload.call(files: [ image_upload("kitchen.png") ],
          community_id: community.id, floorplan_id: floorplan.id)

        assert_equal 0, result.count
        assert_equal 1, result.updated_count
        assert result.success?
      end

      existing.reload
      assert_equal community.id, existing.community_id
      assert_equal floorplan.id, existing.floorplan_id
    end

    test "a re-upload never clears placement the photo already had" do
      community = Community.create!(code: "1682", name: "Bradbury")
      existing = existing_photo
      existing.update!(community: community)

      BatchUpload.call(files: [ image_upload("kitchen.png") ]) # no location chosen

      assert_equal community.id, existing.reload.community_id
    end

    # The line that protects the hand-placed pins.
    test "a re-upload leaves tags, pins and processed state untouched" do
      community = Community.create!(code: "1682", name: "Bradbury")
      existing = existing_photo
      sku = Sku.create!(product_code: "AAA")
      PhotoSku.create!(photo: existing, sku: sku, variant_value: "Chrome", pos_x: 0.4, pos_y: 0.6)
      existing.update!(status: :complete, processed_by: users(:one), processed_at: Time.current)

      BatchUpload.call(files: [ image_upload("kitchen.png") ], community_id: community.id)

      existing.reload
      assert existing.complete?
      assert_equal users(:one), existing.processed_by
      tag = existing.photo_skus.sole
      assert_equal "Chrome", tag.variant_value
      assert_in_delta 0.4, tag.pos_x
    end

    test "the redundant re-uploaded blob is purged rather than kept" do
      existing_photo
      before = ActiveStorage::Blob.count

      perform_enqueued_jobs { BatchUpload.call(files: [ image_upload("kitchen.png") ]) }

      assert_equal before, ActiveStorage::Blob.count
    end

    test "update_existing: false keeps a genuine second copy" do
      existing_photo

      assert_difference -> { Photo.count }, 1 do
        result = BatchUpload.call(files: [ image_upload("kitchen.png") ], update_existing: false)
        assert_equal 1, result.count
        assert_equal 0, result.updated_count
      end
    end

    test "re-uploads arriving as signed_ids are folded in too" do
      existing = existing_photo
      dup = ActiveStorage::Blob.create_and_upload!(
        io: File.open(image_path_for("kitchen.png")), filename: "again.png",
        content_type: "image/png"
      )
      community = Community.create!(code: "1682", name: "Bradbury")

      assert_no_difference -> { Photo.count } do
        result = BatchUpload.call(signed_ids: [ dup.signed_id ], community_id: community.id)
        assert_equal 1, result.updated_count
      end

      assert_equal community.id, existing.reload.community_id
    end

    test "an invalid signed_id is reported, not fatal" do
      result = BatchUpload.call(signed_ids: [ "garbage" ])
      assert_equal 0, result.count
      assert_not result.success?
      assert_match(/could not be attached/, result.errors.to_sentence)
    end

    test "reports unsupported files and empty input" do
      bad = Rack::Test::UploadedFile.new(file_fixture("sample.png"), "text/plain", original_filename: "notes.txt")
      result = BatchUpload.call(files: [ bad ])
      assert_not result.success?
      assert_match(/unsupported/, result.errors.to_sentence)

      empty = BatchUpload.call(files: [])
      assert_not empty.success?
      assert_match(/at least one/, empty.errors.to_sentence)
    end
  end
end
