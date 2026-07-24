class CreateSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :steps do |t|
      t.references :community, null: false, foreign_key: { on_delete: :cascade }
      t.string :step, null: false
      t.integer :sortorder
      t.text :area_associations

      t.timestamps
    end
    add_index :steps, [ :community_id, :step ], unique: true
  end
end
