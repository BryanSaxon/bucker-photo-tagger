class CreateStepSubcategories < ActiveRecord::Migration[8.1]
  def change
    create_table :step_subcategories do |t|
      t.references :step_category, null: false, foreign_key: { on_delete: :cascade }
      t.string :name
      t.integer :sortorder

      t.timestamps
    end
  end
end
