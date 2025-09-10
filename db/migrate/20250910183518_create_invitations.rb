class CreateInvitations < ActiveRecord::Migration[7.0]
  def change
    create_table :invitations do |t|
      t.string :token, null: false
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.datetime :accepted_at

      t.timestamps
    end
    add_index :invitations, :token, unique: true
  end
end