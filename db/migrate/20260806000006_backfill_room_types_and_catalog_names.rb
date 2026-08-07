class BackfillRoomTypesAndCatalogNames < ActiveRecord::Migration[8.1]
  # One-shot data backfill so the new filtering and room vocabulary are live the
  # moment this deploys, rather than waiting for someone to run a rake task or
  # for the next full catalog sync.
  #
  # A migration rather than a task because migrations run exactly once and
  # record that they did. Everything here is derived from data already in the
  # database, so it needs no NewStar credentials and is safe to run during
  # Render's preDeployCommand.
  def up
    RoomType.load_vocabulary!
    classify_rooms
    Catalog::SkuEnricher.call(fetch_selections: LotSelection.exists?)

    say "room types: #{RoomType.count}; sellable: #{Sku.where(sellable: true).count}/#{Sku.count}"
  rescue => e
    # Never block a deploy on a backfill. Without it the app still works: the
    # sellable filter fails open and the room picker just starts empty, both
    # recoverable by running `rails catalog:backfill` afterwards.
    say "Backfill skipped: #{e.class}: #{e.message}"
    say "Run `bin/rails catalog:backfill` once the cause is resolved."
  end

  def down
    # Derived data only — nothing here is authored by hand, so there is nothing
    # to restore. Photos keep their room_type_id; the columns go with the
    # migrations that added them.
  end

  private

  def classify_rooms
    ids = Rooms::Classifier.ids_by_key
    Room.find_each do |room|
      room_type_id = Rooms::Classifier.room_type_id_for(room.room_code, room.room_desc, ids: ids)
      room.update_columns(room_type_id: room_type_id) unless room.room_type_id == room_type_id
    end

    Photo.where.not(room_id: nil).where(room_type_id: nil).includes(:room).find_each do |photo|
      next if photo.room&.room_type_id.blank?

      photo.update_columns(room_type_id: photo.room.room_type_id)
    end
  end
end
