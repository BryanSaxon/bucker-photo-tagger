require "test_helper"

class SkusFlowTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "sku library requires authentication" do
    get skus_path
    assert_redirected_to new_session_path
  end

  test "sku library lists and filters skus" do
    Sku.create!(product_code: "AAA", short_description: "Faucet", category_code: "07CabTop")
    Sku.create!(product_code: "BBB", short_description: "Cabinet", category_code: "12Cabs")
    sign_in_as(@user)

    get skus_path
    assert_response :success
    assert_match "Faucet", @response.body

    get skus_path(q: "cabinet")
    assert_match "Cabinet", @response.body
    assert_no_match "Faucet", @response.body
  end

  test "sku show page renders catalog details and image metadata" do
    sku = Sku.create!(product_code: "AAA", short_description: "Faucet", category_code: "07CabTop",
      image_filename: "AAA.JPG", image_mimetype: "image/jpeg", image_file_id: "F-1", images_count: 3)
    sign_in_as(@user)

    get sku_path(sku)
    assert_response :success
    assert_match "Faucet", @response.body
    assert_match "AAA.JPG", @response.body
    assert_match "07CabTop", @response.body
  end

  test "sku show page handles a sku with no image" do
    sku = Sku.create!(product_code: "NOIMG", short_description: "Plain")
    sign_in_as(@user)

    get sku_path(sku)
    assert_response :success
    assert_match "No image", @response.body
  end

  test "triggering a sync enqueues the job and creates a running record" do
    sign_in_as(@user)

    assert_enqueued_with(job: SkuSyncJob) do
      assert_difference -> { SkuSync.count }, 1 do
        post sku_syncs_path
      end
    end
    assert_redirected_to skus_path
    assert SkuSync.latest.running?
  end

  test "does not start a second sync while one is running" do
    SkuSync.create!(status: :running, started_at: Time.current)
    sign_in_as(@user)

    assert_no_difference -> { SkuSync.count } do
      post sku_syncs_path
    end
    assert_redirected_to skus_path
  end
end
