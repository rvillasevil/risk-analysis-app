class AddUniqueIndexForClientRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    client_role = User.roles[:client]

    add_index :risk_assistants,
              :user_id,
              unique: true,
              where: <<~SQL.squish,
                EXISTS (
                  SELECT 1
                  FROM users
                  WHERE users.id = risk_assistants.user_id
                    AND users.role = #{client_role}
                )
              SQL
              name: "index_risk_assistants_on_user_id_unique_for_client"
  end
end
