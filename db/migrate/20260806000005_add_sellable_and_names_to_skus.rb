class AddSellableAndNamesToSkus < ActiveRecord::Migration[8.1]
  def change
    # Has this product ever been selected in a real home? Derived from
    # lot_selections during sync. Defaults to true so that a database which has
    # never run a full sync offers the whole catalog rather than nothing —
    # the filter fails open.
    add_column :skus, :sellable, :boolean, null: false, default: true
    add_index :skus, :sellable

    # Human-readable category names. NewStar only gives codes on the product
    # record (05FlrTil, 12Cabs) but names on the lot-selection and option
    # payloads, so these are filled in from there during sync.
    add_column :skus, :category_name, :string
    add_column :skus, :subcategory_name, :string
  end
end
