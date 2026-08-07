class AddVariantValueToPhotoSkus < ActiveRecord::Migration[8.1]
  def change
    # NOT NULL DEFAULT '' rather than nullable, for two reasons that hold
    # regardless of how much data exists:
    #   1. Postgres treats NULLs as distinct in a unique index, so a nullable
    #      column would leave the composite index below unenforcing for exactly
    #      the rows that are most common (no variant recorded).
    #   2. Migrations run in Render's preDeployCommand, so the previously
    #      deployed code briefly inserts without this column. A constant default
    #      keeps those inserts valid and behaving as they did before.
    # Existing rows become '' — "variant not specified", the old semantics.
    add_column :photo_skus, :variant_value, :string, null: false, default: ""

    # The identity of a tag is (photo, sku, variant): the same faucet in matte
    # black and in chrome is two tags on one photo.
    remove_index :photo_skus, column: %i[photo_id sku_id], unique: true,
      name: "index_photo_skus_on_photo_id_and_sku_id"
    add_index :photo_skus, %i[photo_id sku_id variant_value], unique: true,
      name: "index_photo_skus_on_photo_sku_variant"

    # "Where is this finish installed?" — the query the feature exists for.
    add_index :photo_skus, %i[sku_id variant_value],
      name: "index_photo_skus_on_sku_id_and_variant_value"
  end
end
