class CreateSkuImages < ActiveRecord::Migration[8.1]
  def change
    create_table :sku_images do |t|
      t.references :sku, null: false, foreign_key: { on_delete: :cascade }
      t.string :product_code, null: false
      t.string :file_id, null: false
      t.string :filename
      t.string :filemimetype
      t.string :title
      t.text :description
      t.string :source_type
      t.string :attribute1
      t.string :attribute2
      t.boolean :archived, null: false, default: false
      t.string :source_modified_at

      t.timestamps
    end
    add_index :sku_images, :product_code
    add_index :sku_images, :file_id, unique: true
  end
end
