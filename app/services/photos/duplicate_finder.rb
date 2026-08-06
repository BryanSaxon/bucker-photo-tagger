module Photos
  # Finds an existing Photo whose image is byte-identical to a given blob.
  #
  # Uses the checksum Active Storage already records. For direct uploads the
  # browser computes it before the bytes are sent, so the match is exact rather
  # than a filename heuristic.
  class DuplicateFinder
    def self.for_blob(blob)
      return nil if blob.nil? || blob.checksum.blank?

      Photo.joins(image_attachment: :blob)
        .where(active_storage_blobs: { checksum: blob.checksum, byte_size: blob.byte_size })
        .where.not(id: owner_id(blob))
        .order(:created_at)
        .first
    end

    # The photo this blob is already attached to, if any — so a blob is never
    # reported as a duplicate of its own photo.
    def self.owner_id(blob)
      ActiveStorage::Attachment
        .where(blob_id: blob.id, record_type: "Photo", name: "image")
        .pick(:record_id)
    end
  end
end
