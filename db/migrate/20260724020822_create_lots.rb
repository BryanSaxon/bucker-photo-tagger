class CreateLots < ActiveRecord::Migration[8.1]
  def change
    create_table :lots do |t|
      t.references :community, null: false, foreign_key: { on_delete: :cascade }
      # Best-effort link: lots reference a model only by free-text
      # model_description, so the association may be absent.
      t.references :floorplan, null: true, foreign_key: { on_delete: :nullify }
      t.string :lot, null: false
      t.string :lot_address
      t.string :lot_status
      t.string :lot_type
      t.string :model_description
      t.decimal :base_model_price, precision: 12, scale: 2
      t.decimal :lot_price, precision: 12, scale: 2
      t.decimal :lot_premium, precision: 12, scale: 2
      t.decimal :gross_sale, precision: 12, scale: 2
      t.decimal :options_total, precision: 12, scale: 2

      t.timestamps
    end
    add_index :lots, [ :community_id, :lot ], unique: true
  end
end
