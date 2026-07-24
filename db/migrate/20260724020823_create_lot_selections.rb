class CreateLotSelections < ActiveRecord::Migration[8.1]
  def change
    create_table :lot_selections do |t|
      t.references :lot, null: false, foreign_key: { on_delete: :cascade }
      # A selection's product/room may not resolve to a synced Sku/Room row.
      t.references :sku, null: true, foreign_key: { on_delete: :nullify }
      t.references :room, null: true, foreign_key: { on_delete: :nullify }
      t.string :kind
      t.string :product_code
      t.string :product_description
      t.string :short_description
      t.string :attribute1_desc
      t.string :attribute1
      t.string :attribute2_desc
      t.string :attribute2
      t.string :model_description
      t.string :category_code
      t.string :category_name
      t.string :subcategory_code
      t.string :subcategory_name
      t.decimal :unit_price, precision: 12, scale: 2
      t.decimal :quantity, precision: 10, scale: 2
      t.string :uofm
      t.decimal :gross_sale, precision: 12, scale: 2
      t.string :room_code
      t.string :room_description

      t.timestamps
    end
    add_index :lot_selections, :product_code
  end
end
