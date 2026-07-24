class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :integer, null: false, default: 0
    # Set when an admin invites a user; cleared once they set their password.
    add_column :users, :invited_at, :datetime
  end
end
