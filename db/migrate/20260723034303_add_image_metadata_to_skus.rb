class AddImageMetadataToSkus < ActiveRecord::Migration[8.1]
  def change
    # Image metadata synced from the NewStart /product_images endpoint. The API
    # exposes these details (and a file_id) but no downloadable image bytes, so
    # we store the metadata and can render the image later if byte download is
    # ever enabled upstream.
    add_column :skus, :image_filename, :string
    add_column :skus, :image_mimetype, :string
    add_column :skus, :image_file_id, :string
    add_column :skus, :images_count, :integer, null: false, default: 0
  end
end
