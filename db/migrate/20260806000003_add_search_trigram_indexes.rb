class AddSearchTrigramIndexes < ActiveRecord::Migration[8.1]
  # ILIKE '%…%' can't use a btree, and SKU search runs on every keystroke of the
  # tagging panel. Trigram indexes make those scans indexable.
  #
  # Deliberately standalone and rescued: migrations run in Render's
  # preDeployCommand, so if the database role lacks CREATE on the database an
  # unguarded enable_extension would fail the whole deploy — including the
  # fixes that matter. Search still works without these, just via a seq scan,
  # which at ~2k SKUs is single-digit milliseconds.
  INDEXES = {
    "index_photos_on_name_trgm" => [ :photos, :name ],
    "index_skus_on_short_description_trgm" => [ :skus, :short_description ],
    "index_skus_on_product_code_trgm" => [ :skus, :product_code ],
    "index_skus_on_attribute1_trgm" => [ :skus, :attribute1 ],
    "index_photo_skus_on_variant_value_trgm" => [ :photo_skus, :variant_value ]
  }.freeze

  def up
    enable_extension "pg_trgm"

    INDEXES.each do |name, (table, column)|
      next if index_name_exists?(table, name)

      add_index table, column, using: :gin, opclass: :gin_trgm_ops, name: name
    end
  rescue ActiveRecord::StatementInvalid => e
    say "Skipped trigram indexes: #{e.class}: #{e.message.lines.first&.strip}"
    say "Search is unaffected — it falls back to a sequential scan."
  end

  def down
    INDEXES.each do |name, (table, _column)|
      remove_index table, name: name if index_name_exists?(table, name)
    end
  end
end
