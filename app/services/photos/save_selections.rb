module Photos
  # Persists a processor's selections from the processing screen: the optional
  # placement (community / floorplan / room) and the set of tagged SKUs (with
  # optional pin coordinates), then marks the photo complete and records who
  # processed it. Placement is not required — a photo can be completed with any,
  # all, or none of it set.
  class SaveSelections
    Result = Struct.new(:success?, :error, keyword_init: true)

    def self.call(...) = new(...).call

    # sku_entries: array of { id:, pos_x:, pos_y:, variant_value: } hashes
    # (string keys ok). variant_value is the finish/colour/size chosen for that
    # product in this photo, blank when the product has no variants.
    def initialize(photo:, community_id:, floorplan_id:, sku_entries:, user:,
      room_id: nil, room_type_id: nil)
      @photo = photo
      @community_id = community_id.presence
      @floorplan_id = floorplan_id.presence
      @room_id = room_id.presence
      @room_type_id = room_type_id.presence
      @sku_entries = Array(sku_entries)
      @user = user
    end

    def call
      Photo.transaction do
        # room_id is deliberately not written. The processing screen no longer
        # offers the catalog-room picker, so it submits nothing for it — and
        # assigning nil would erase the room captured at upload time. It stays
        # as whatever ingest recorded, and still feeds room-type derivation.
        @photo.update!(community_id: resolved_community_id, floorplan_id: @floorplan_id,
          room_type_id: resolved_room_type_id)
        reconcile_skus
        @photo.mark_complete!(@user)
      end

      Result.new(success?: true)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.record.errors.full_messages.to_sentence)
    end

    private

    # Placement is optional; back-fill the community from a chosen floorplan or
    # room so the stored context stays internally consistent.
    def resolved_community_id
      @community_id ||
        (@floorplan_id && Floorplan.where(id: @floorplan_id).pick(:community_id)) ||
        (@room_id && Room.where(id: @room_id).pick(:community_id))
    end

    # A specific catalog room already knows its type, so choosing one is enough
    # — the designer doesn't have to set both.
    def resolved_room_type_id
      @room_type_id || (@room_id && Room.where(id: @room_id).pick(:room_type_id))
    end

    # Rebuild the photo's SKU tags to exactly match the submitted selection,
    # preserving/updating pin coordinates and dropping any deselected tags.
    #
    # Keyed on (sku_id, variant_value), not sku_id alone: one product can appear
    # twice in a photo under two finishes, and keying on the sku alone would let
    # the second silently overwrite the first.
    def reconcile_skus
      incoming = @sku_entries.filter_map { |entry|
        sku_id = value(entry, :id).to_i
        next if sku_id.zero?

        [ [ sku_id, value(entry, :variant_value).to_s.strip ], entry ]
      }.to_h

      keep = incoming.keys
      @photo.photo_skus.find_each do |photo_sku|
        photo_sku.destroy unless keep.include?([ photo_sku.sku_id, photo_sku.variant_value ])
      end

      incoming.each do |(sku_id, variant_value), entry|
        photo_sku = @photo.photo_skus.find_or_initialize_by(sku_id: sku_id, variant_value: variant_value)
        photo_sku.pos_x = value(entry, :pos_x).presence
        photo_sku.pos_y = value(entry, :pos_y).presence
        photo_sku.save!
      end
    end

    # Entries arrive from params with string keys; callers and tests may use
    # symbols.
    def value(entry, key) = entry[key] || entry[key.to_s]
  end
end
