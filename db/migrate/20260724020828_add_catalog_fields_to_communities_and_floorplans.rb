class AddCatalogFieldsToCommunitiesAndFloorplans < ActiveRecord::Migration[8.1]
  def change
    add_column :communities, :product_library_code, :string

    # code == the API's project_code; make it the unique upsert key.
    remove_index :communities, :code
    add_index :communities, :code, unique: true

    # Floorplan is the API's "Model" (a model + elevation offered in a
    # community). Enrich it with the fields from the models2 endpoint.
    change_table :floorplans, bulk: true do |t|
      t.string  :model_description
      t.decimal :base_model_price, precision: 12, scale: 2
      t.text    :base_model_rooms
      t.integer :square_feet
      t.integer :bed_count
      t.integer :bath_count
      t.integer :half_bath_count
      t.integer :garage_count
      t.boolean :discontinued, null: false, default: false
      t.boolean :sellable, null: false, default: true
    end

    # Natural key for upserting models from the catalog.
    add_index :floorplans, [ :community_id, :name, :elevation ], unique: true,
      name: "index_floorplans_on_community_model_elevation"
  end
end
