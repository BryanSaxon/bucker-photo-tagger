class AddDuplicateDetectionToPhotos < ActiveRecord::Migration[8.1]
  def change
    # Active Storage already records a checksum on every upload — including
    # direct uploads, where the browser computes it before any bytes are sent.
    # Nothing read it until now. Matched together with byte_size: MD5 is not
    # collision-resistant, and pairing it with size costs nothing.
    add_index :active_storage_blobs, %i[checksum byte_size],
      name: "index_active_storage_blobs_on_checksum_and_byte_size"

    # Cheap pre-check for "the same export dropped in again", the common case,
    # answerable before any bytes move.
    add_index :active_storage_blobs, %i[filename byte_size],
      name: "index_active_storage_blobs_on_filename_and_byte_size"

    # For the minority case: the designer wants a second copy anyway, so it's
    # flagged rather than hidden.
    add_reference :photos, :duplicate_of, null: true,
      foreign_key: { to_table: :photos, on_delete: :nullify }
  end
end
