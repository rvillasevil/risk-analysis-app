class AddShareTokenToRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    add_column :risk_assistants, :share_token, :string
    add_index :risk_assistants, :share_token, unique: true
  end
end
