class AddNameToRiskAssistants < ActiveRecord::Migration[7.0]
  def change
    add_column :risk_assistants, :name, :string
  end
end
