class CreateClientInvitations < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:risk_assistants, :client_owned)
      add_column :risk_assistants, :client_owned, :boolean, default: false, null: false
    end

    if column_exists?(:users, :role)
      execute <<~SQL.squish
        UPDATE risk_assistants
        SET client_owned = TRUE
        FROM users
        WHERE risk_assistants.user_id = users.id
          AND users.role = 1
      SQL
    end

    if index_exists?(:risk_assistants, :user_id, name: "index_risk_assistants_on_user_id_unique_for_client")
      remove_index :risk_assistants, name: "index_risk_assistants_on_user_id_unique_for_client"
    end

    add_index :risk_assistants, :user_id,
              unique: true,
              where: "client_owned",
              name: "index_risk_assistants_on_user_id_unique_for_client"
  end

  def down
    remove_index :risk_assistants, name: "index_risk_assistants_on_user_id_unique_for_client", if_exists: true
    remove_column :risk_assistants, :client_owned, if_exists: true
  end
end
