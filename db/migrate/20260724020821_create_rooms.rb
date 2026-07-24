class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.references :community, null: false, foreign_key: { on_delete: :cascade }
      t.string :room_code, null: false
      t.string :room_desc

      t.timestamps
    end
    add_index :rooms, [ :community_id, :room_code ], unique: true
  end
end
