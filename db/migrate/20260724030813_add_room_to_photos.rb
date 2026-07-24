class AddRoomToPhotos < ActiveRecord::Migration[8.1]
  def change
    add_reference :photos, :room, null: true, foreign_key: { on_delete: :nullify }
  end
end
