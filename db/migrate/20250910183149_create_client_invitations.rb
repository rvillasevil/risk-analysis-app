class CreateClientInvitations < ActiveRecord::Migration[7.0]
  def change
    create_table :client_invitations do |t|
      t.string :email
      t.string :token
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.datetime :accepted_at      

      t.timestamps
    end
  end
end
