module Photos
  # Persists a processor's selections from the processing screen: the community,
  # the floorplan, and the set of tagged SKUs (with optional pin coordinates),
  # then marks the photo complete and records who processed it.
  class SaveSelections
    Result = Struct.new(:success?, :error, keyword_init: true)

    def self.call(...) = new(...).call

    # sku_entries: array of { id:, pos_x:, pos_y: } hashes (string keys ok).
    def initialize(photo:, community_id:, floorplan_id:, sku_entries:, user:, room_id: nil)
      @photo = photo
      @community_id = community_id.presence
      @floorplan_id = floorplan_id.presence
      @room_id = room_id.presence
      @sku_entries = Array(sku_entries)
      @user = user
    end

    def call
      error = validation_error
      return Result.new(success?: false, error: error) if error

      Photo.transaction do
        @photo.update!(community_id: @community_id, floorplan_id: @floorplan_id, room_id: @room_id)
        reconcile_skus
        @photo.mark_complete!(@user)
      end

      Result.new(success?: true)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.record.errors.full_messages.to_sentence)
    end

    private

    def validation_error
      return "Please choose a community." if @community_id.blank?
      return "Please choose a floorplan." if @floorplan_id.blank?

      nil
    end

    # Rebuild the photo's SKU tags to exactly match the submitted selection,
    # preserving/updating pin coordinates and dropping any deselected SKUs.
    def reconcile_skus
      incoming = @sku_entries.index_by { |e| e[:id].presence&.to_i || e["id"].to_i }
      incoming.delete(0)

      @photo.photo_skus.where.not(sku_id: incoming.keys).destroy_all

      incoming.each do |sku_id, entry|
        photo_sku = @photo.photo_skus.find_or_initialize_by(sku_id: sku_id)
        photo_sku.pos_x = (entry[:pos_x] || entry["pos_x"]).presence
        photo_sku.pos_y = (entry[:pos_y] || entry["pos_y"]).presence
        photo_sku.save!
      end
    end
  end
end
