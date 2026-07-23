class CreateSkus < ActiveRecord::Migration[8.1]
  def change
    create_table :skus do |t|
      # product_code is the API's unique business key (there is no numeric id
      # or "name" field in the source catalog — short_description is the label).
      t.string :product_code, null: false
      t.string :short_description
      t.string :category_code
      t.string :subcategory_code
      t.string :attribute1_desc
      t.text :attribute1
      t.string :image_flag
      # Raw source timestamp string from the API (malformed float-derived format).
      t.string :source_modified_at

      t.timestamps
    end

    add_index :skus, :product_code, unique: true
    add_index :skus, :category_code
    add_index :skus, :subcategory_code
  end
end
