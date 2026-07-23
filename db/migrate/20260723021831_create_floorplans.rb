class CreateFloorplans < ActiveRecord::Migration[8.1]
  def change
    create_table :floorplans do |t|
      t.string :name
      t.string :elevation
      t.string :code
      t.references :community, null: false, foreign_key: true

      t.timestamps
    end
  end
end
