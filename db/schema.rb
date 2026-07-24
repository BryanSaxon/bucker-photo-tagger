# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_24_013838) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "communities", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_communities_on_code"
  end

  create_table "floorplans", force: :cascade do |t|
    t.string "code"
    t.bigint "community_id", null: false
    t.datetime "created_at", null: false
    t.string "elevation"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["community_id"], name: "index_floorplans_on_community_id"
  end

  create_table "photo_skus", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "photo_id", null: false
    t.float "pos_x"
    t.float "pos_y"
    t.bigint "sku_id", null: false
    t.datetime "updated_at", null: false
    t.index ["photo_id", "sku_id"], name: "index_photo_skus_on_photo_id_and_sku_id", unique: true
    t.index ["photo_id"], name: "index_photo_skus_on_photo_id"
    t.index ["sku_id"], name: "index_photo_skus_on_sku_id"
  end

  create_table "photos", force: :cascade do |t|
    t.bigint "community_id"
    t.datetime "created_at", null: false
    t.bigint "floorplan_id"
    t.string "name", null: false
    t.datetime "processed_at"
    t.bigint "processed_by_id"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["community_id"], name: "index_photos_on_community_id"
    t.index ["floorplan_id"], name: "index_photos_on_floorplan_id"
    t.index ["name"], name: "index_photos_on_name"
    t.index ["processed_by_id"], name: "index_photos_on_processed_by_id"
    t.index ["status"], name: "index_photos_on_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sku_images", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.string "attribute1"
    t.string "attribute2"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "file_id", null: false
    t.string "filemimetype"
    t.string "filename"
    t.string "product_code", null: false
    t.bigint "sku_id", null: false
    t.string "source_modified_at"
    t.string "source_type"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["file_id"], name: "index_sku_images_on_file_id", unique: true
    t.index ["product_code"], name: "index_sku_images_on_product_code"
    t.index ["sku_id"], name: "index_sku_images_on_sku_id"
  end

  create_table "sku_syncs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "synced_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_sku_syncs_on_created_at"
  end

  create_table "skus", force: :cascade do |t|
    t.text "attribute1"
    t.string "attribute1_desc"
    t.string "category_code"
    t.datetime "created_at", null: false
    t.string "image_file_id"
    t.string "image_filename"
    t.string "image_flag"
    t.string "image_mimetype"
    t.integer "images_count", default: 0, null: false
    t.string "product_code", null: false
    t.string "short_description"
    t.string "source_modified_at"
    t.string "subcategory_code"
    t.datetime "updated_at", null: false
    t.index ["category_code"], name: "index_skus_on_category_code"
    t.index ["product_code"], name: "index_skus_on_product_code", unique: true
    t.index ["subcategory_code"], name: "index_skus_on_subcategory_code"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "floorplans", "communities"
  add_foreign_key "photo_skus", "photos"
  add_foreign_key "photo_skus", "skus"
  add_foreign_key "photos", "communities"
  add_foreign_key "photos", "floorplans"
  add_foreign_key "photos", "users", column: "processed_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "sku_images", "skus", on_delete: :cascade
end
