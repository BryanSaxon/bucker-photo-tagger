class CreatePhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :photos do |t|
      t.string :name, null: false
      # 0 = unprocessed, 1 = complete (see Photo::STATUSES)
      t.integer :status, null: false, default: 0
      t.datetime :processed_at

      # A photo has no community/floorplan/processor until it is processed,
      # so these associations are optional.
      t.references :community, null: true, foreign_key: true
      t.references :floorplan, null: true, foreign_key: true
      t.references :processed_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :photos, :status
    add_index :photos, :name
  end
end
