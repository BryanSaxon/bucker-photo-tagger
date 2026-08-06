module Catalog
  # Upserts a community's models (stored as Floorplan) from the models2 payload,
  # and the community-wide room dictionary embedded inline on each model. Prunes
  # models/rooms that left the catalog (models referenced by photos are kept).
  class ModelsSyncer
    def self.call(community, models, **opts)
      new(community, models, **opts).call
    end

    def initialize(community, models)
      @community = community
      @models = models || []
    end

    # Returns the number of models (floorplans) upserted.
    def call
      return 0 if @models.blank?

      sync_rooms
      sync_models
    end

    private

    def sync_models
      now = Time.current
      rows = @models.filter_map do |m|
        name = m["model"].presence
        next unless name

        {
          community_id: @community.id,
          name: name,
          elevation: m["elevation"],
          model_description: m["model_description"],
          base_model_price: Casts.decimal(m["base_model_price"]),
          base_model_rooms: m["base_model_rooms"],
          square_feet: Casts.integer(m["square_feet"]),
          bed_count: Casts.integer(m["bed_count"]),
          bath_count: Casts.integer(m["bath_count"]),
          half_bath_count: Casts.integer(m["half_bath_count"]),
          garage_count: Casts.integer(m["garage_count"]),
          discontinued: Casts.boolean(m["discontinued"]) || false,
          sellable: m.key?("sellable") ? (Casts.boolean(m["sellable"]) || false) : true,
          created_at: now,
          updated_at: now
        }
      end
      rows.uniq! { |r| [ r[:name], r[:elevation] ] }

      Floorplan.upsert_all(rows, unique_by: :index_floorplans_on_community_model_elevation,
        update_only: %i[model_description base_model_price base_model_rooms square_feet
                        bed_count bath_count half_bath_count garage_count discontinued sellable])

      prune_models(rows)
      rows.size
    end

    def prune_models(rows)
      keep = rows.map { |r| [ r[:name], r[:elevation] ] }.to_set
      stale = @community.floorplans.where.missing(:photos).reject do |f|
        keep.include?([ f.name, f.elevation ])
      end
      Floorplan.where(id: stale.map(&:id)).delete_all if stale.any?
    end

    # The room dictionary is repeated inline on every model; collect distinct
    # room_code => room_desc across all of them.
    def sync_rooms
      now = Time.current
      ids = Rooms::Classifier.ids_by_key
      seen = {}
      @models.each do |m|
        Array(m["rooms"]).each do |room|
          code = room["room_code"].presence
          next if code.nil? || seen.key?(code)
          desc = room["room_desc"]
          seen[code] = { community_id: @community.id, room_code: code,
                         room_desc: desc, created_at: now, updated_at: now,
                         room_type_id: Rooms::Classifier.room_type_id_for(code, desc, ids: ids) }
        end
      end
      rows = seen.values
      return if rows.empty?

      Room.upsert_all(rows, unique_by: :index_rooms_on_community_id_and_room_code,
        update_only: %i[room_desc room_type_id])

      # Never prune a room that carries real work. photos.room_id is
      # ON DELETE SET NULL, so an unguarded delete here silently unassigns the
      # room from already-tagged photos whenever a payload omits or reshapes a
      # code. (prune_models above guards floorplans the same way.)
      @community.rooms
        .where.not(room_code: rows.map { |r| r[:room_code] })
        .where.missing(:photos)
        .where.missing(:lot_selections)
        .delete_all
    end
  end
end
