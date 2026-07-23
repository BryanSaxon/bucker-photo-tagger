class CreatePhotoSkus < ActiveRecord::Migration[8.1]
  def change
    create_table :photo_skus do |t|
      t.references :photo, null: false, foreign_key: true
      t.references :sku, null: false, foreign_key: true
      # Optional normalized (0.0–1.0) location of the SKU within the photo,
      # used later to render buyers' selections in place. Null = not pinned.
      t.float :pos_x
      t.float :pos_y

      t.timestamps
    end

    add_index :photo_skus, [ :photo_id, :sku_id ], unique: true
  end
end
