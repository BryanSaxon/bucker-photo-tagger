class CreateRoomTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :room_types do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.integer :sort_order, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :room_types, :key, unique: true
    add_index :room_types, %i[active sort_order]

    # Both nullable, so the previously deployed code keeps working during
    # Render's preDeployCommand window. `rooms` keeps its NewStart codes and
    # gains a classification; photos record the designer-facing type directly.
    add_reference :rooms, :room_type, null: true, foreign_key: { on_delete: :nullify }
    add_reference :photos, :room_type, null: true, foreign_key: { on_delete: :nullify }
  end
end
