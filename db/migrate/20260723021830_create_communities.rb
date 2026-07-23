class CreateCommunities < ActiveRecord::Migration[8.1]
  def change
    create_table :communities do |t|
      t.string :name, null: false
      t.string :code

      t.timestamps
    end

    add_index :communities, :code
  end
end
