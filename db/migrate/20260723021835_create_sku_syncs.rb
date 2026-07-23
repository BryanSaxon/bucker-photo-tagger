class CreateSkuSyncs < ActiveRecord::Migration[8.1]
  def change
    create_table :sku_syncs do |t|
      # 0 = running, 1 = completed, 2 = failed (see SkuSync::STATUSES)
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :synced_count, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :sku_syncs, :created_at
  end
end
