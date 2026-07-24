class CreateOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :options do |t|
      t.references :community, null: false, foreign_key: { on_delete: :cascade }
      t.references :sku, null: true, foreign_key: { on_delete: :nullify }
      # Linked to a model by free-text model + elev, so may not resolve.
      t.references :floorplan, null: true, foreign_key: { on_delete: :nullify }
      t.string :product_code
      t.string :model
      t.string :elev
      t.string :model_description
      t.string :description
      t.string :short_description
      t.string :category
      t.string :category_code
      t.string :subcategory
      t.string :subcategory_code
      t.string :option_type
      t.decimal :unit_price, precision: 12, scale: 2
      t.decimal :qty, precision: 10, scale: 2
      t.string :uofm
      t.decimal :gross_sale, precision: 12, scale: 2
      t.string :add_floor_area
      t.text :room_replacement_add
      t.text :room_replacement_remove
      t.string :source_modified_at

      t.timestamps
    end
    add_index :options, :product_code
  end
end
