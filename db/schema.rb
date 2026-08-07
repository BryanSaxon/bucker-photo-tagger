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

ActiveRecord::Schema[8.1].define(version: 2026_08_06_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

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
    t.index ["checksum", "byte_size"], name: "index_active_storage_blobs_on_checksum_and_byte_size"
    t.index ["filename", "byte_size"], name: "index_active_storage_blobs_on_filename_and_byte_size"
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
    t.string "product_library_code"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_communities_on_code", unique: true
  end

  create_table "floorplans", force: :cascade do |t|
    t.decimal "base_model_price", precision: 12, scale: 2
    t.text "base_model_rooms"
    t.integer "bath_count"
    t.integer "bed_count"
    t.string "code"
    t.bigint "community_id", null: false
    t.datetime "created_at", null: false
    t.boolean "discontinued", default: false, null: false
    t.string "elevation"
    t.integer "garage_count"
    t.integer "half_bath_count"
    t.string "model_description"
    t.string "name"
    t.boolean "sellable", default: true, null: false
    t.integer "square_feet"
    t.datetime "updated_at", null: false
    t.index ["community_id", "name", "elevation"], name: "index_floorplans_on_community_model_elevation", unique: true
    t.index ["community_id"], name: "index_floorplans_on_community_id"
  end

  create_table "lot_selections", force: :cascade do |t|
    t.string "attribute1"
    t.string "attribute1_desc"
    t.string "attribute2"
    t.string "attribute2_desc"
    t.string "category_code"
    t.string "category_name"
    t.datetime "created_at", null: false
    t.decimal "gross_sale", precision: 12, scale: 2
    t.string "kind"
    t.bigint "lot_id", null: false
    t.string "model_description"
    t.string "product_code"
    t.string "product_description"
    t.decimal "quantity", precision: 10, scale: 2
    t.string "room_code"
    t.string "room_description"
    t.bigint "room_id"
    t.string "short_description"
    t.bigint "sku_id"
    t.string "subcategory_code"
    t.string "subcategory_name"
    t.decimal "unit_price", precision: 12, scale: 2
    t.string "uofm"
    t.datetime "updated_at", null: false
    t.index ["lot_id"], name: "index_lot_selections_on_lot_id"
    t.index ["product_code"], name: "index_lot_selections_on_product_code"
    t.index ["room_id"], name: "index_lot_selections_on_room_id"
    t.index ["sku_id"], name: "index_lot_selections_on_sku_id"
  end

  create_table "lots", force: :cascade do |t|
    t.decimal "base_model_price", precision: 12, scale: 2
    t.bigint "community_id", null: false
    t.datetime "created_at", null: false
    t.bigint "floorplan_id"
    t.decimal "gross_sale", precision: 12, scale: 2
    t.string "lot", null: false
    t.string "lot_address"
    t.decimal "lot_premium", precision: 12, scale: 2
    t.decimal "lot_price", precision: 12, scale: 2
    t.string "lot_status"
    t.string "lot_type"
    t.string "model_description"
    t.decimal "options_total", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.index ["community_id", "lot"], name: "index_lots_on_community_id_and_lot", unique: true
    t.index ["community_id"], name: "index_lots_on_community_id"
    t.index ["floorplan_id"], name: "index_lots_on_floorplan_id"
  end

  create_table "options", force: :cascade do |t|
    t.string "add_floor_area"
    t.string "category"
    t.string "category_code"
    t.bigint "community_id", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "elev"
    t.bigint "floorplan_id"
    t.decimal "gross_sale", precision: 12, scale: 2
    t.string "model"
    t.string "model_description"
    t.string "option_type"
    t.string "product_code"
    t.decimal "qty", precision: 10, scale: 2
    t.text "room_replacement_add"
    t.text "room_replacement_remove"
    t.string "short_description"
    t.bigint "sku_id"
    t.string "source_modified_at"
    t.string "subcategory"
    t.string "subcategory_code"
    t.decimal "unit_price", precision: 12, scale: 2
    t.string "uofm"
    t.datetime "updated_at", null: false
    t.index ["community_id"], name: "index_options_on_community_id"
    t.index ["floorplan_id"], name: "index_options_on_floorplan_id"
    t.index ["product_code"], name: "index_options_on_product_code"
    t.index ["sku_id"], name: "index_options_on_sku_id"
  end

  create_table "photo_skus", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "photo_id", null: false
    t.float "pos_x"
    t.float "pos_y"
    t.bigint "sku_id", null: false
    t.datetime "updated_at", null: false
    t.string "variant_value", default: "", null: false
    t.index ["photo_id", "sku_id", "variant_value"], name: "index_photo_skus_on_photo_sku_variant", unique: true
    t.index ["photo_id"], name: "index_photo_skus_on_photo_id"
    t.index ["sku_id", "variant_value"], name: "index_photo_skus_on_sku_id_and_variant_value"
    t.index ["sku_id"], name: "index_photo_skus_on_sku_id"
    t.index ["variant_value"], name: "index_photo_skus_on_variant_value_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "photos", force: :cascade do |t|
    t.bigint "community_id"
    t.datetime "created_at", null: false
    t.bigint "duplicate_of_id"
    t.bigint "floorplan_id"
    t.string "name", null: false
    t.datetime "processed_at"
    t.bigint "processed_by_id"
    t.bigint "room_id"
    t.bigint "room_type_id"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["community_id"], name: "index_photos_on_community_id"
    t.index ["duplicate_of_id"], name: "index_photos_on_duplicate_of_id"
    t.index ["floorplan_id"], name: "index_photos_on_floorplan_id"
    t.index ["name"], name: "index_photos_on_name"
    t.index ["name"], name: "index_photos_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["processed_by_id"], name: "index_photos_on_processed_by_id"
    t.index ["room_id"], name: "index_photos_on_room_id"
    t.index ["room_type_id"], name: "index_photos_on_room_type_id"
    t.index ["status"], name: "index_photos_on_status"
  end

  create_table "room_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active", "sort_order"], name: "index_room_types_on_active_and_sort_order"
    t.index ["key"], name: "index_room_types_on_key", unique: true
  end

  create_table "rooms", force: :cascade do |t|
    t.bigint "community_id", null: false
    t.datetime "created_at", null: false
    t.string "room_code", null: false
    t.string "room_desc"
    t.bigint "room_type_id"
    t.datetime "updated_at", null: false
    t.index ["community_id", "room_code"], name: "index_rooms_on_community_id_and_room_code", unique: true
    t.index ["community_id"], name: "index_rooms_on_community_id"
    t.index ["room_type_id"], name: "index_rooms_on_room_type_id"
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
    t.string "category_name"
    t.datetime "created_at", null: false
    t.string "image_file_id"
    t.string "image_filename"
    t.string "image_flag"
    t.string "image_mimetype"
    t.integer "images_count", default: 0, null: false
    t.string "product_code", null: false
    t.boolean "sellable", default: true, null: false
    t.string "short_description"
    t.string "source_modified_at"
    t.string "subcategory_code"
    t.string "subcategory_name"
    t.datetime "updated_at", null: false
    t.index ["attribute1"], name: "index_skus_on_attribute1_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["category_code"], name: "index_skus_on_category_code"
    t.index ["product_code"], name: "index_skus_on_product_code", unique: true
    t.index ["product_code"], name: "index_skus_on_product_code_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["sellable"], name: "index_skus_on_sellable"
    t.index ["short_description"], name: "index_skus_on_short_description_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["subcategory_code"], name: "index_skus_on_subcategory_code"
  end

  create_table "step_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "sortorder"
    t.bigint "step_id", null: false
    t.datetime "updated_at", null: false
    t.index ["step_id"], name: "index_step_categories_on_step_id"
  end

  create_table "step_subcategories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "sortorder"
    t.bigint "step_category_id", null: false
    t.datetime "updated_at", null: false
    t.index ["step_category_id"], name: "index_step_subcategories_on_step_category_id"
  end

  create_table "steps", force: :cascade do |t|
    t.text "area_associations"
    t.bigint "community_id", null: false
    t.datetime "created_at", null: false
    t.integer "sortorder"
    t.string "step", null: false
    t.datetime "updated_at", null: false
    t.index ["community_id", "step"], name: "index_steps_on_community_id_and_step", unique: true
    t.index ["community_id"], name: "index_steps_on_community_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.string "email_address", null: false
    t.datetime "invited_at"
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "floorplans", "communities"
  add_foreign_key "lot_selections", "lots", on_delete: :cascade
  add_foreign_key "lot_selections", "rooms", on_delete: :nullify
  add_foreign_key "lot_selections", "skus", on_delete: :nullify
  add_foreign_key "lots", "communities", on_delete: :cascade
  add_foreign_key "lots", "floorplans", on_delete: :nullify
  add_foreign_key "options", "communities", on_delete: :cascade
  add_foreign_key "options", "floorplans", on_delete: :nullify
  add_foreign_key "options", "skus", on_delete: :nullify
  add_foreign_key "photo_skus", "photos"
  add_foreign_key "photo_skus", "skus"
  add_foreign_key "photos", "communities"
  add_foreign_key "photos", "floorplans"
  add_foreign_key "photos", "photos", column: "duplicate_of_id", on_delete: :nullify
  add_foreign_key "photos", "room_types", on_delete: :nullify
  add_foreign_key "photos", "rooms", on_delete: :nullify
  add_foreign_key "photos", "users", column: "processed_by_id"
  add_foreign_key "rooms", "communities", on_delete: :cascade
  add_foreign_key "rooms", "room_types", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "sku_images", "skus", on_delete: :cascade
  add_foreign_key "step_categories", "steps", on_delete: :cascade
  add_foreign_key "step_subcategories", "step_categories", on_delete: :cascade
  add_foreign_key "steps", "communities", on_delete: :cascade
end
