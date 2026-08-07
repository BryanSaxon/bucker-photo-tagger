namespace :room_types do
  desc "Load the room-type vocabulary and classify existing rooms and photos"
  task backfill: :environment do
    RoomType.load_vocabulary!
    ids = Rooms::Classifier.ids_by_key

    rooms = 0
    Room.find_each do |room|
      room_type_id = Rooms::Classifier.room_type_id_for(room.room_code, room.room_desc, ids: ids)
      next if room.room_type_id == room_type_id

      room.update_columns(room_type_id: room_type_id)
      rooms += 1
    end

    # Photos already placed against a specific catalog room inherit its type.
    photos = 0
    Photo.where.not(room_id: nil).where(room_type_id: nil).includes(:room).find_each do |photo|
      next if photo.room&.room_type_id.blank?

      photo.update_columns(room_type_id: photo.room.room_type_id)
      photos += 1
    end

    puts "Classified #{rooms} rooms; back-filled room type on #{photos} photos."
  end
end
